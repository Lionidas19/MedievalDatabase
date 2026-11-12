import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/widgets/focus_ring.dart';

/// The ring is for the keyboard. A mouse reader must never see it, and a
/// keyboard reader must always be able to.
void main() {
  testWidgets('the ring appears for the keyboard and not for the mouse',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FocusRing(child: child!),
      home: Scaffold(
        body: Column(
          children: [
            TextButton(onPressed: () {}, child: const Text('one')),
            TextButton(onPressed: () {}, child: const Text('two')),
          ],
        ),
      ),
    ));

    RenderObject ring() => tester.renderObject(find
        .descendant(
            of: find.byType(FocusRing), matching: find.byType(CustomPaint))
        .last);

    // A click focuses nothing visibly.
    await tester.tap(find.text('one'));
    await tester.pumpAndSettle();
    expect(ring(), isNot(paints..rrect()));

    // Tab does: the halo, then the ring.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(ring(), paints..rrect()..rrect());

    // And the mouse puts it away again.
    await tester.tap(find.text('two'));
    await tester.pumpAndSettle();
    expect(ring(), isNot(paints..rrect()));
  });
}
