import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/screens/tour/tour.dart';
import 'package:price_explorer/state/view_mode.dart';

/// The tour from the keyboard alone: the arrows move it, Enter presses Next,
/// Escape leaves. With no targets registered every pointed step is skipped,
/// which leaves the ones that point at nothing; that is enough to walk.
void main() {
  testWidgets('the tour answers to the arrows, Enter and Escape',
      (tester) async {
    var mode = ViewMode.advanced;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Tour.start(
              context,
              currentMode: () => mode,
              // The app redraws on a change of screen, and the tour waits
              // for that frame before measuring; a bare assignment never
              // schedules one.
              setMode: (m) {
                mode = m;
                tester.binding.scheduleFrame();
              },
            ),
            child: const Text('start'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(Tour.isRunning, isTrue);

    String counter() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => RegExp(r'^\d+ of \d+$').hasMatch(s));

    final first = counter();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final second = counter();
    expect(second, isNot(first));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(counter(), first);

    // Next has focus from the start, so Enter needs no help to press it.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(counter(), second);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(Tour.isRunning, isFalse);
    expect(mode, ViewMode.advanced, reason: 'it puts the reader back');
  });
}
