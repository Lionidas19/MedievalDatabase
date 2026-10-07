import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/models/models.dart';
import 'package:price_explorer/screens/advanced/filter_bar.dart';
import 'package:price_explorer/services/statistics.dart';
import 'package:price_explorer/state/view_preferences.dart';
import 'package:provider/provider.dart';

/// The toolbar fails the way the table does: by throwing during a render pass
/// on a branch nobody happened to open.
///
/// The case these exist for is the one the researcher reported — a unit the
/// selection cannot be expressed in — because that branch had a `Flexible`
/// wrapped inside a `Padding` instead of sitting directly in its `Row`. That
/// is a ParentDataWidget error, and a release build paints a failed widget as
/// a plain grey rectangle, so the toolbar and the whole table under it
/// disappeared behind one. It is reachable only by choosing a unit first and
/// then narrowing to records that cannot use it, which is why it survived
/// every manual pass.
void main() {
  PriceEntry entry({String? dimension = 'mass'}) {
    final measure = MetricItem('m1', 'Quarter', 279931.44, dimension: dimension);
    return PriceEntry(
      entryId: 'e1',
      legacyEntryNo: 1,
      year: 1275,
      locality: 'Cranfield',
      county: 'Bedfordshire',
      category: 'Food',
      subcategory: 'Grain',
      specific: 'Wheat',
      unit1: 1,
      measure1: measure,
      valuationMeasure: measure,
      shillings: 4,
      pence: 4,
    );
  }

  Widget harness({
    required PriceStats stats,
    bool dense = false,
    bool compact = false,
    bool brief = false,
    MetricItem? outputUnit,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ViewPreferences()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: FilterBar(
            filters: const FilterState(),
            onFiltersChanged: (_) {},
            counties: const ['Bedfordshire', 'Norfolk'],
            categories: const ['Food', 'Agricultural Labour'],
            outputUnits: [
              MetricItem.recordedUnit,
              MetricItem('kg', 'Kilograms', 1000, dimension: 'mass'),
            ],
            outputUnit: outputUnit ?? MetricItem.recordedUnit,
            onOutputUnitChanged: (_) {},
            minYear: 1270,
            maxYear: 1291,
            resultCount: 1,
            totalCount: 1,
            undatedTotal: 0,
            estimating: false,
            onEstimatingChanged: (_) {},
            estimateCount: 0,
            dense: dense,
            compact: compact,
            entries: [entry()],
            onNewEntry: () {},
            stats: stats,
            statsWithEstimates: null,
            brief: brief,
            onReset: () {},
          ),
        ),
      ),
    );
  }

  group('the figures panel', () {
    testWidgets('renders when nothing in the selection can be priced',
        (tester) async {
      await tester.pumpWidget(harness(
        stats: PriceStats.empty,
        outputUnit: MetricItem('kg', 'Kilograms', 1000, dimension: 'mass'),
      ));
      await tester.pumpAndSettle();

      // A ParentDataWidget error throws here rather than failing an
      // expectation, so reaching this line at all is most of the test.
      expect(tester.takeException(), isNull);

      // His wording: the figures should still show up, marked NA, rather
      // than dropping off the screen.
      expect(find.text('NA'), findsWidgets);
      expect(
        find.textContaining('none of these can be priced per Kilograms'),
        findsOneWidget,
      );
    });

    testWidgets('shows the figures when there are figures to show',
        (tester) async {
      await tester.pumpWidget(harness(
        stats: PriceStats.from(const [12.0, 14.0, 16.0]),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('NA'), findsNothing);
      expect(find.textContaining('of 3'), findsOneWidget);
    });

    testWidgets('the empty case lays out at every shape the bar takes',
        (tester) async {
      for (final (dense, compact, brief) in const [
        (false, false, false),
        (true, false, false),
        (false, true, false),
        (false, false, true),
      ]) {
        await tester.pumpWidget(harness(
          stats: PriceStats.empty,
          dense: dense,
          compact: compact,
          brief: brief,
          outputUnit: MetricItem('kg', 'Kilograms', 1000, dimension: 'mass'),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'dense=$dense compact=$compact brief=$brief');
      }
    });
  });
}
