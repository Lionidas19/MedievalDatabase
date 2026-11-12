import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/models/models.dart';
import 'package:price_explorer/screens/advanced/entry_columns.dart';
import 'package:price_explorer/screens/advanced/entry_table.dart';
import 'package:price_explorer/state/view_preferences.dart';
import 'package:price_explorer/theme.dart';

/// The table lays itself out by hand — fixed column widths inside a horizontal
/// scroll view, with pinned group headers over a fixed-extent list. That is
/// the kind of layout that fails by throwing during a render pass rather than
/// by looking wrong, and it fails only at sizes nobody happened to try.
///
/// These tests pump it at every detail level and every density, at a window
/// narrower than the widest column set, which is where an unbounded-width or
/// overflow assertion would fire.
void main() {
  PricedEntry priced({
    int? year = 1275,
    double? perUnit = 12.5,
    bool comparable = true,
    String? dimension = 'mass',
  }) {
    final measure = MetricItem('m1', 'Quarter', 279931.44, dimension: dimension);
    final entry = PriceEntry(
      entryId: 'e-$year-$perUnit',
      legacyEntryNo: 42,
      year: year,
      locality: 'Cranfield',
      county: 'Bedfordshire',
      category: 'Food',
      subcategory: 'Grain',
      specific: 'Wheat',
      unit1: 16,
      measure1: measure,
      valuationMeasure: measure,
      shillings: 4,
      pence: 6,
      page: 123,
      timePeriodName: 'Michaelmas',
      statusInfo: 'sold to the abbey',
      sourceCitation: 'Rogers, vol. 2',
    );
    return PricedEntry(
      entry: entry,
      calc: entry.calculate(),
      perUnit: perUnit,
      comparable: comparable,
    );
  }

  Widget harness(Widget child, {Size size = const Size(900, 600)}) =>
      MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          theme: AppTheme.build(
            variant: ThemeVariant.parchment,
            brightness: Brightness.light,
          ),
          home: Scaffold(body: child),
        ),
      );

  EntryTable table({
    required DetailLevel level,
    required List<EntryGroup> groups,
    TableDensity density = TableDensity.comfortable,
    bool grouped = false,
  }) =>
      EntryTable(
        groups: groups,
        columns: columnsFor(level, 'Kilograms', modernYear: 2017),
        rowHeight: density.rowHeight,
        sortColumnId: 'year',
        ascending: true,
        onSort: (_) {},
        onOpen: (_) {},
        onRead: (_) {},
        unitName: 'Kilograms',
        showGroupHeaders: grouped,
      );

  EntryGroup group(String label, List<PricedEntry> rows) {
    final values = [
      for (final r in rows)
        if (r.perUnit != null) r.perUnit!
    ]..sort();
    return EntryGroup(
      label: label,
      rows: rows,
      median: values.isEmpty ? null : values[values.length ~/ 2],
      pricedCount: values.length,
    );
  }

  for (final level in DetailLevel.values) {
    testWidgets('renders at ${level.name} without a layout failure',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(harness(table(
        level: level,
        groups: [
          group('', [priced(), priced(year: 1280, perUnit: 3)]),
        ],
      )));

      expect(tester.takeException(), isNull);
      // The columns every level carries.
      expect(find.text('Year'), findsOneWidget);
      expect(find.text('Pence per selected unit'), findsOneWidget);
    });
  }

  testWidgets('the wider levels add columns rather than shrinking them',
      (tester) async {
    final basics = columnsFor(DetailLevel.basics, 'Kilograms');
    final everything = columnsFor(DetailLevel.everything, 'Kilograms');

    expect(everything.length, greaterThan(basics.length));
    // A column that appears at both levels keeps its width: the table scrolls
    // sideways instead of squeezing what was already there.
    for (final b in basics) {
      final same = everything.firstWhere((c) => c.label == b.label);
      expect(same.width, b.width, reason: 'width of "${b.label}" changed');
    }
  });

  // Every column, without exception. Year, Place, Item and Quantity once went
  // without, on the reasoning that their headings said it all; the researcher
  // wrote an explanation for each of them, because "Year" here means a year
  // that starts at Michaelmas and "Place" stops at the county.
  test('every column explains itself', () {
    for (final level in DetailLevel.values) {
      for (final column in columnsFor(level, 'Kilograms')) {
        expect(column.explanation, isNotNull,
            reason: '"${column.label}" ($level) has no explanation');
        expect(column.explanation, isNot(contains('*')),
            reason: '"${column.label}" — tooltips render no markup');
      }
    }
  });

  test('the time of year counts its entries rather than quoting them', () {
    String? timeOfYear(EntryCounts? counts) => columnsFor(
          DetailLevel.everything,
          'Kilograms',
          counts: counts,
        ).firstWhere((c) => c.id == 'timeOfYear').explanation;

    expect(timeOfYear((total: 7440, timed: 363, dated: 108)),
        contains('Only 363 of the 7440 entries'));
    // No counts, no figure: a stale one is what this replaced.
    expect(timeOfYear(null), isNot(contains('Only')));
  });

  test('every column can be sorted, and by something sensible', () {
    for (final level in DetailLevel.values) {
      final columns = columnsFor(level, 'Kilograms');
      for (final c in columns) {
        expect(c.sortKey, isNotNull, reason: '"${c.label}" cannot be sorted');
      }
      // Ids are what a sort is remembered by, so they have to be unique and
      // must not move when the output unit is renamed.
      final ids = columns.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate column id');
    }
    final kg = columnsFor(DetailLevel.everything, 'Kilograms');
    final lb = columnsFor(DetailLevel.everything, 'Tower Pound');
    expect(kg.map((c) => c.id), lb.map((c) => c.id),
        reason: 'changing the output unit must not change a column id');
  });

  test('sort keys order numbers as numbers and text case-blind', () {
    expect(compareSortKeys(9, 10), lessThan(0));
    expect(compareSortKeys(9.5, 9.4), greaterThan(0));
    expect(compareSortKeys('bushel', 'Bushel'), 0);
    expect(compareSortKeys('Acre', 'bushel'), lessThan(0));
  });

  test('columns are ordered the way a row is read', () {
    final labels =
        columnsFor(DetailLevel.everything, 'Kilograms').map((c) => c.label);

    // When and where, then what, then what it cost, then what that works out
    // to, then the working, then the rest of the record, then the citation.
    final order = labels.toList();
    int at(String label) => order.indexOf(label);
    expect(at('Entry'), lessThan(at('Year')));
    expect(at('Year'), lessThan(at('Time of year')));
    expect(at('Time of year'), lessThan(at('Place')));
    expect(at('Item'), lessThan(at('Quantity')));
    expect(at('Quantity'), lessThan(at('Price as recorded')));
    expect(at('Price as recorded'), lessThan(at('Pence per selected unit')));
    expect(at('Pence per selected unit'), lessThan(at('Measure 1')));
    expect(at('Measure 1'), lessThan(at('Status / info')));
    expect(at('Status / info'), lessThan(at('Source')));
    expect(at('Source'), lessThan(at('Page')));
    expect(at('Page'), order.length - 1);
  });

  test('each run of columns is marked so the table can draw the seam', () {
    final columns = columnsFor(DetailLevel.everything, 'Kilograms');
    final seams = [
      for (final c in columns)
        if (c.startsGroup) c.label,
    ];
    expect(seams, [
      'Price as recorded',
      'Pence per selected unit',
      'Quantity in metric',
      'Status / info',
      'Source',
    ]);
    // The first column never draws one — there is nothing to its left.
    expect(columns.first.startsGroup, isFalse);
  });

  test('the shorter levels explain the columns they do show', () {
    // A reader on Basics gets fewer columns, not fewer explanations for them.
    for (final level in DetailLevel.values) {
      for (final column in columnsFor(level, 'Kilograms')) {
        if (column.label == 'Price as recorded' ||
            column.label.startsWith('Pence per ')) {
          expect(column.explanation, isNotNull, reason: '$level ${column.label}');
        }
      }
    }
  });

  testWidgets('group headings report the sample the median came from',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(harness(table(
      level: DetailLevel.basics,
      grouped: true,
      groups: [
        group('1275', [
          priced(),
          // Counted by the head, asked for per kilogram: excluded, not zeroed.
          priced(perUnit: null, comparable: false, dimension: 'count'),
        ]),
      ],
    )));

    expect(tester.takeException(), isNull);
    // The heading and the Year cells under it all read 1275, so the heading is
    // identified by what only it carries.
    expect(find.text('1275'), findsWidgets);
    expect(find.text('2 entries'), findsOneWidget);
    expect(find.textContaining('from 1 of 2'), findsOneWidget);
  });

  // Grouped, the table opens as a list of headings with their medians, which
  // is the comparison the researcher asked for; a heading opens its rows.
  testWidgets('groups start closed and open from their heading or the bar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(harness(table(
      level: DetailLevel.basics,
      grouped: true,
      groups: [
        group('1275', [priced(year: 1275)]),
        group('1280', [priced(year: 1280)]),
      ],
    )));
    // Only the headings: no row under either.
    expect(find.text('Cranfield, Bedfordshire'), findsNothing);
    expect(find.textContaining('2 groups'), findsOneWidget);

    await tester.tap(find.text('1275'));
    await tester.pumpAndSettle();
    expect(find.text('Cranfield, Bedfordshire'), findsOneWidget);
    expect(find.text('1 of 2 groups open'), findsOneWidget);

    await tester.tap(find.text('Open all'));
    await tester.pumpAndSettle();
    expect(find.text('Cranfield, Bedfordshire'), findsNWidgets(2));

    await tester.tap(find.text('Close all'));
    await tester.pumpAndSettle();
    expect(find.text('Cranfield, Bedfordshire'), findsNothing);
  });

  testWidgets('an unpriced cell explains itself rather than showing a bare dash',
      (tester) async {
    final wrongKind =
        priced(perUnit: null, comparable: false, dimension: 'count');
    expect(
      missingPerUnitReason(wrongKind, 'Kilograms'),
      contains('does not convert'),
    );
    expect(missingPerUnitReason(priced(), 'Kilograms'), isNull);
  });

  testWidgets('compact density still lays out at every level', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final level in DetailLevel.values) {
      await tester.pumpWidget(harness(
        table(
          level: level,
          density: TableDensity.compact,
          grouped: true,
          groups: [group('Food', [priced()])],
        ),
        size: const Size(700, 500),
      ));
      expect(tester.takeException(), isNull, reason: level.name);
    }
  });

  // The reading aids make every word bigger and wider, and this table is laid
  // out by hand at fixed widths: the heading budget in CLAUDE.md assumes the
  // standard size. Each reading typeface at the largest size with the wider
  // spacing, at both densities, in a window narrower than the table.
  testWidgets('the reading aids still lay out at every level', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final font in ReadingFont.values) {
      for (final density in TableDensity.values) {
        for (final level in DetailLevel.values) {
          await tester.pumpWidget(MediaQuery(
            data: MediaQueryData(
              size: const Size(700, 500),
              textScaler: TextScaler.linear(TextSize.largest.scale),
            ),
            child: MaterialApp(
              theme: AppTheme.build(
                variant: ThemeVariant.parchment,
                brightness: Brightness.light,
                density: density,
                font: font,
                widerSpacing: true,
              ),
              home: Scaffold(
                body: table(
                  level: level,
                  density: density,
                  grouped: true,
                  groups: [
                    group('Food', [priced()])
                  ],
                ),
              ),
            ),
          ));
          expect(tester.takeException(), isNull,
              reason: '${font.name} ${density.name} ${level.name}');
        }
      }
    }
  });

  // The safety-critical one. A tap used to open the editor, and a tester
  // changed a record they only meant to look at — with no way afterwards to
  // say which record it had been.
  testWidgets('a row tap opens the record to read, never to edit',
      (tester) async {
    PricedEntry? read;
    PriceEntry? edited;

    await tester.pumpWidget(harness(EntryTable(
      groups: [
        group('', [priced()])
      ],
      columns: columnsFor(DetailLevel.basics, 'Kilograms'),
      rowHeight: TableDensity.comfortable.rowHeight,
      sortColumnId: 'year',
      ascending: true,
      onSort: (_) {},
      onOpen: (e) => edited = e,
      onRead: (p) => read = p,
      unitName: 'Kilograms',
      showGroupHeaders: false,
    )));

    // The place cell: inside the row, and well away from the edit button.
    await tester.tap(find.text('Cranfield, Bedfordshire'));
    await tester.pump();

    expect(read, isNotNull, reason: 'a tap should open the record to read');
    expect(edited, isNull, reason: 'a tap must never open the editor');
  });

  // The researcher asked for a modern equivalent visible "with no effort",
  // so it is at every detail level rather than behind Everything.
  test('modern money shows from Basics, and only when there are factors', () {
    for (final level in DetailLevel.values) {
      final withFactors = columnsFor(level, 'Kilograms', modernYear: 2017);
      expect(withFactors.map((c) => c.id), contains('modernPrice'),
          reason: '$level should carry the modern price');
      // Named as a price, beside the recorded one. "In 2026 money" said in
      // what and not per what, and was read as the per-unit figure.
      expect(withFactors.firstWhere((c) => c.id == 'modernPrice').label,
          'Price in 2017 £');
      expect(withFactors.map((c) => c.id), contains('modernPerUnit'),
          reason: '$level should carry the modern price per unit');

      // No factors in the database means no column, rather than a column of
      // dashes that reads as a broken app.
      final without = columnsFor(level, 'Kilograms');
      expect(without.map((c) => c.id), isNot(contains('modernPrice')));
      expect(without.map((c) => c.id), isNot(contains('modernPerUnit')));
    }
  });

  test('modern money is sortable and explains itself', () {
    final columns = columnsFor(DetailLevel.everything, 'Kilograms',
        modernYear: 2017);
    for (final id in ['modernPrice', 'modernPerUnit']) {
      final column = columns.firstWhere((c) => c.id == id);
      expect(column.sortKey, isNotNull, reason: '$id should be sortable');
      expect(column.explanation, isNotNull,
          reason: '$id is a derived figure and must say what it is');
      // It is a guide to scale, not a valuation. If that caveat ever
      // disappears the column starts claiming more than it can support.
      expect(column.explanation, contains('scale'));
    }
  });

  // What the researcher asked for, level by level, after using it.
  test('Basics answers what, how much, and what one unit costs today', () {
    final ids = columnsFor(DetailLevel.basics, 'Kilograms', modernYear: 2017)
        .map((c) => c.id)
        .toList();
    expect(ids, contains('quantity'));
    expect(ids.last, 'modernPerUnit');
  });

  test('More detail has the metric quantity but not the page', () {
    final ids = columnsFor(DetailLevel.detailed, 'Kilograms', modernYear: 2017)
        .map((c) => c.id);
    expect(ids, containsAll(['modernPrice', 'modernPerUnit', 'totalMetric']));
    expect(ids, isNot(contains('page')));
    expect(columnsFor(DetailLevel.everything, 'Kilograms').map((c) => c.id),
        contains('page'));
  });

  // The modern per-unit figure has to be withheld wherever the pence one is.
  // Read off the calculation instead, it answered per kilogram for a row that
  // cannot be priced per kilogram, beside a dash in the pence column.
  test('the modern per-unit figure follows the pence one', () {
    final column = columnsFor(DetailLevel.basics, 'Kilograms', modernYear: 2017)
        .firstWhere((c) => c.id == 'modernPerUnit');
    final withheld = priced(perUnit: null, comparable: false);
    expect(withheld.calc.modernPerOutputY, isNull,
        reason: 'precondition: no factor passed, so nothing to leak');
    expect(column.value(withheld), '—');

    final e = withheld.entry;
    final shown = PricedEntry(
        entry: e, calc: e.calculate(), perUnit: 18.755,
        modernPerUnit: 72.87, comparable: true);
    expect(column.value(shown), '£72.87');
  });

  // The researcher asked for the database to be usable from the keyboard
  // alone. Page Up and Down did nothing, and neither did the arrows: the
  // table held no focus for them to reach.
  testWidgets('the keyboard walks the rows and opens one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final rows = [
      for (var i = 0; i < 200; i++)
        PricedEntry(
          entry: PriceEntry(
            entryId: 'row$i',
            legacyEntryNo: i,
            year: 1270,
            locality: 'Cranfield',
          ),
          calc: PriceEntry(entryId: 'x').calculate(),
          perUnit: 1,
          comparable: true,
        ),
    ];
    PricedEntry? read;
    var found = 0;

    await tester.pumpWidget(harness(EntryTable(
      groups: [group('', rows)],
      columns: columnsFor(DetailLevel.everything, 'Kilograms'),
      rowHeight: TableDensity.comfortable.rowHeight,
      sortColumnId: 'year',
      ascending: true,
      onSort: (_) {},
      onOpen: (_) {},
      onRead: (p) => read = p,
      onFind: () => found++,
      unitName: 'Kilograms',
      showGroupHeaders: false,
    )));
    await tester.pump();

    ScrollPosition axis(Axis direction) => tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((s) => s.position)
        .firstWhere((p) => p.axis == direction);
    final down = axis(Axis.vertical);
    final across = axis(Axis.horizontal);

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    Future<String?> openCurrent() async {
      read = null;
      await press(LogicalKeyboardKey.enter);
      return read?.entry.entryId;
    }

    // Nothing is highlighted until a key asks for it, so Enter does nothing.
    expect(await openCurrent(), isNull);

    // The first press lands on the top row in view rather than moving past it.
    await press(LogicalKeyboardKey.arrowDown);
    expect(await openCurrent(), 'row0');
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.arrowUp);
    expect(await openCurrent(), 'row1');

    // J and K do the same, for readers with the habit from Gmail or GitHub.
    await press(LogicalKeyboardKey.keyJ);
    await press(LogicalKeyboardKey.keyJ);
    await press(LogicalKeyboardKey.keyK);
    expect(await openCurrent(), 'row2');

    // A page moves the highlight a screenful and scrolls to keep it in view.
    await press(LogicalKeyboardKey.pageDown);
    await press(LogicalKeyboardKey.pageDown);
    expect(down.pixels, greaterThan(0));
    final paged = await openCurrent();
    expect(int.parse(paged!.substring(3)), greaterThan(10));

    await press(LogicalKeyboardKey.end);
    expect(await openCurrent(), 'row199');
    expect(down.pixels, down.maxScrollExtent);

    await press(LogicalKeyboardKey.home);
    expect(await openCurrent(), 'row0');
    expect(down.pixels, 0);

    // Escape puts the highlight away again.
    await press(LogicalKeyboardKey.escape);
    expect(await openCurrent(), isNull);

    await press(LogicalKeyboardKey.arrowRight);
    expect(across.pixels, greaterThan(0));

    await press(LogicalKeyboardKey.slash);
    expect(found, 1, reason: '/ should ask for the search box');
  });
}
