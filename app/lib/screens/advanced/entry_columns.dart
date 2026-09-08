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

String _dash(Object? v) {
  final s = v?.toString() ?? '';
  return s.isEmpty ? '—' : s;
}

String _num(double? v) => v == null ? '—' : formatPence(v);

/// The column set for [level], pricing against a unit named [unitName].
///
/// Ordered the way a row is read aloud rather than the way the spreadsheet
/// happened to store it: when and where, what it was, what it cost, what that
/// works out to, how the figure was reached, what else the record says, and
/// where it came from. [EntryColumn.startsGroup] marks each of those turns, so
/// the table can draw the seam.
List<EntryColumn> columnsFor(DetailLevel level, String unitName) {
  final detailed = level.atLeastDetailed;
  final everything = level.isEverything;

  return [
    // ------------------------------------------------ when, where, what --
    if (detailed)
      EntryColumn(
        id: 'entryNo',
        label: 'Entry',
        width: 88,
        numeric: true,
        sortKey: (p) => p.entry.legacyEntryNo,
        explanation: 'The row this record occupies in the source spreadsheet, '
            'for checking an entry against the original. New entries carry on '
            'from the last one.',
        value: (p) => _dash(p.entry.legacyEntryNo),
      ),
    EntryColumn(
      id: 'year',
      label: 'Year',
      sortKey: (p) => p.entry.year,
      width: 72,
      numeric: true,
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
            'Month, season or feast day, exactly as the record gives '
            'it — the source mixes all three in one column. Only 363 of the '
            '7,800 entries carry one at all.',
        value: (p) => _dash(p.entry.timePeriodName),
      ),
    EntryColumn(
      id: 'place',
      label: 'Place',
      sortKey: (p) => p.entry.placeLabel,
      width: 200,
      value: (p) => p.entry.placeLabel,
    ),
    EntryColumn(
      id: 'item',
      label: 'Item',
      sortKey: (p) => p.entry.categoryLabel,
      width: 260,
      value: (p) => p.entry.categoryLabel,
    ),
    if (detailed)
      EntryColumn(
        id: 'quantity',
        label: 'Quantity',
        sortKey: (p) => p.entry.unit1,
        width: 190,
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
          'The price exactly as the record gives it, in pounds, '
          'shillings and pence. Often a price per unit rather than a total — '
          'think of an hourly wage rather than a pay slip.',
      value: (p) => p.entry.priceLabel,
    ),
    if (everything)
      EntryColumn(
        id: 'priceInPence',
        label: 'Price in pence',
        sortKey: (p) => p.calc.priceInPence,
        width: 132,
        numeric: true,
        explanation:
            'The same recorded price expressed in pence alone: '
            'pounds x 240 + shillings x 12 + pence.',
        value: (p) => _num(p.calc.priceInPence),
      ),

    // ------------------------------------------- what that works out to --
    EntryColumn(
      id: 'perUnit',
      label: 'Pence per $unitName',
      sortKey: (p) => p.perUnit,
      width: 190,
      numeric: true,
      startsGroup: true,
      explanation:
          'The headline figure: pence per $unitName, worked out for '
          'this entry rather than stored. Choose a different unit with '
          '"Price per" above the table. A figure shown as "~ 0.19" is an '
          'estimate from neighbouring years, never a record.',
      value: (p) => p.perUnit != null
          ? _num(p.perUnit)
          : p.estimate != null
          ? '~ ${formatPence(p.estimate!.value)}'
          : '—',
      cellTooltip: (p) => p.estimate != null
          ? p.estimate!.explain(unitName, p.entry.year ?? 0)
          : missingPerUnitReason(p, unitName),
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
    if (everything) ...[
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
        explanation: 'Whatever the record noted that fits in no other column.',
        value: (p) => _dash(p.entry.statusInfo),
      ),
      EntryColumn(
        id: 'food',
        label: 'Food',
        sortKey: (p) => p.entry.food,
        width: 170,
        explanation:
            'Payment in kind — where the work was paid in bread, '
            'wine or lodging rather than in coin.',
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
    if (detailed)
      EntryColumn(
        id: 'page',
        label: 'Page',
        sortKey: (p) => p.entry.page,
        width: 92,
        numeric: true,
        startsGroup: !everything,
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
