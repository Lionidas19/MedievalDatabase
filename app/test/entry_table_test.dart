import 'package:flutter/material.dart';
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
        columns: columnsFor(level, 'Kilograms'),
        rowHeight: density.rowHeight,
        sortColumnId: 'year',
        ascending: true,
        onSort: (_) {},
        onOpen: (_) {},
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
      expect(find.text('Pence per Kilograms'), findsOneWidget);
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

  // Named, not positional. The rule was first written as "everything from
  // Time of year rightwards", which stopped describing anything the moment the
  // columns were reordered — Time of year now sits second, beside Year. These
  // four are the ones whose heading is the whole explanation.
  const selfEvident = {'Year', 'Place', 'Item', 'Quantity'};

  test('every column explains itself unless its name already does', () {
    for (final level in DetailLevel.values) {
      for (final column in columnsFor(level, 'Kilograms')) {
        if (selfEvident.contains(column.label)) {
          expect(column.explanation, isNull,
              reason: '"${column.label}" needs no explaining');
        } else {
          expect(column.explanation, isNotNull,
              reason: '"${column.label}" ($level) has no explanation');
          expect(column.explanation, isNot(contains('*')),
              reason: '"${column.label}" — tooltips render no markup');
        }
      }
    }
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
    expect(at('Price as recorded'), lessThan(at('Pence per Kilograms')));
    expect(at('Pence per Kilograms'), lessThan(at('Measure 1')));
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
      'Pence per Kilograms',
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
}
