import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/models/models.dart';
import 'package:price_explorer/screens/advanced/entry_columns.dart';
import 'package:price_explorer/state/view_preferences.dart';
import 'package:price_explorer/widgets/app_selection.dart';

/// Copying was the researcher's sharpest complaint: everything the app showed
/// had to be typed out again by hand. These pin what lands on the clipboard,
/// which nobody sees until they paste it somewhere that matters.
void main() {
  test('a copied row pastes as headings over values, a dash left empty', () {
    final measure = MetricItem('m1', 'Quarter', 279931.44, dimension: 'mass');
    final entry = PriceEntry(
      entryId: 'e1',
      legacyEntryNo: 42,
      year: 1275,
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
    );
    final priced = PricedEntry(
      entry: entry,
      calc: entry.calculate(),
      perUnit: null,
      comparable: true,
    );
    final columns = columnsFor(DetailLevel.basics, 'Quarter');
    final lines = recordsAsText([priced], columns).split('\n');

    expect(lines, hasLength(2));
    final headings = lines[0].split('\t');
    final values = lines[1].split('\t');
    expect(values, hasLength(headings.length));
    expect(values[headings.indexOf('Year')], '1275');
    expect(values[headings.indexOf('Item')], 'Food / Grain / Wheat');
    expect(values[headings.indexOf('Price as recorded')], '4s 6d');
    // No per-unit figure: an empty cell, not a dash a spreadsheet reads as
    // text and refuses to add up.
    expect(values[headings.indexOf('Pence per selected unit')], '');
    expect(lines.join(), isNot(contains('—')));
  });

  testWidgets('selected text keeps its lines and its columns', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppSelection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A first paragraph.'),
                Text('A second one.'),
                Row(children: [Text('Year'), SizedBox(width: 40), Text('1275')]),
              ],
            ),
          ),
        ),
      ),
    );

    // Drag from the first word to the last, then copy.
    final from = tester.getTopLeft(find.text('A first paragraph.'));
    final to = tester.getBottomRight(find.text('1275'));
    final gesture = await tester.startGesture(
      from + const Offset(1, 1),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(to - const Offset(1, 1));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    // Flutter's own joining gave 'A first paragraph.A second one.Year1275'.
    expect(copied, 'A first paragraph.\nA second one.\nYear\t1275');
  });
}
