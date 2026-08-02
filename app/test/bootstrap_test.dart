import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:price_explorer/main.dart';
import 'package:price_explorer/state/app_controller.dart';

void main() {
  testWidgets('bundled database loads entries on startup', (tester) async {
    await tester.pumpWidget(const PriceExplorerApp());

    AppController? controller;
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      controller = Provider.of<AppController>(
        tester.element(find.byType(PriceExplorerApp)),
        listen: false,
      );
      if (controller.hasData || controller.error != null) break;
    }

    // ignore: avoid_print
    print('hasData=${controller?.hasData} '
        'entries=${controller?.entries.length} '
        'error=${controller?.error} '
        'fileName=${controller?.currentFileName}');

    expect(controller?.error, isNull);
    expect(controller?.hasData, isTrue);
    expect(controller!.entries.length, greaterThan(1000));
  });
}
