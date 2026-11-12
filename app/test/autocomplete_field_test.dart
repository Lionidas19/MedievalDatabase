import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/widgets/autocomplete_field.dart';

/// Found by driving Advanced Search with the keyboard alone: the arrow keys
/// moved through the suggestions, and Enter then chose nothing, so the item
/// was never set and Generate stayed disabled.
void main() {
  testWidgets('arrow keys and Enter choose a suggestion', (tester) async {
    final chosen = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AutocompleteField(
          label: 'Item',
          initialValue: null,
          suggestions: const [
            'Food / Grain / Wheat',
            'Agricultural Labour / Threshing / Wheat (Threshing)',
            'Food / Grain / Barley',
          ],
          onChanged: chosen.add,
        ),
      ),
    ));

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'wheat');
    await tester.pump();

    // Down once from the first suggestion lands on the second.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(chosen.last,
        'Agricultural Labour / Threshing / Wheat (Threshing)');
    expect(find.text('Agricultural Labour / Threshing / Wheat (Threshing)'),
        findsOneWidget,
        reason: 'the box should now hold the suggestion, not "wheat"');
    // Still in the box, so the next Tab goes on to the next field rather
    // than back to the top of the page.
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextField>(),
        isNotNull,
        reason: 'choosing a suggestion must not drop focus');
  });

  // The list opened scrolled halfway down, away from the first suggestion,
  // and no row was marked: a keyboard reader was choosing blind.
  testWidgets('the highlighted suggestion is marked and kept in view',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AutocompleteField(
          label: 'Item',
          initialValue: null,
          suggestions: [for (var i = 0; i < 30; i++) 'Wheat option $i'],
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'wheat');
    await tester.pumpAndSettle();

    String? marked() => tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.selected)
        .map((t) => (t.title as Text).data)
        .firstOrNull;
    double offset() => tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((s) => s.position.axis == Axis.vertical)
        .position
        .pixels;

    expect(marked(), 'Wheat option 0');
    expect(offset(), 0, reason: 'the list opens at its first suggestion');

    Future<void> press(LogicalKeyboardKey key, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }
    }

    await press(LogicalKeyboardKey.arrowDown, 2);
    expect(marked(), 'Wheat option 2');
    expect(offset(), 0, reason: 'no jump while the row is already in view');

    await press(LogicalKeyboardKey.arrowDown, 8);
    expect(marked(), 'Wheat option 10',
        reason: 'scrolled far enough that the marked row is built and shown');

    await press(LogicalKeyboardKey.arrowUp, 9);
    expect(marked(), 'Wheat option 1');
  });

  // Picking from the dropdowns beside it rewrites what the box should say.
  // That was done by keying the field on the choice, which also destroyed it,
  // focus included, whenever a suggestion was chosen *in* it.
  testWidgets('follows a value changed from outside, and keeps focus',
      (tester) async {
    var value = 'Food / Grain / Wheat';
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return AutocompleteField(
            label: 'Item',
            initialValue: value,
            suggestions: const ['Food / Grain / Wheat', 'Food / Grain / Oats'],
            onChanged: (_) {},
          );
        }),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    rebuild(() => value = 'Food / Grain / Oats');
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Food / Grain / Oats');
    expect(field.focusNode!.hasFocus, isTrue,
        reason: 'the same field, updated, not a new one');
  });
}
