// Plain browser file upload/download — works in every browser (unlike the
// File System Access API, which is Chromium-only). The app always starts
// from the bundled default database; opening a file lets you resume editing
// a previously downloaded one, and downloading is how changes are saved.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Opens the browser's file picker restricted to [accept] (default: sqlite
/// files) and returns the picked file's bytes, or null if the user cancelled.
Future<Uint8List?> pickFileBytes({String accept = '.sqlite,.db'}) {
  final completer = Completer<Uint8List?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;

  input.onchange = ((web.Event e) {
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete(null);
      return;
    }
    final file = files.item(0)!;
    file.arrayBuffer().toDart.then((buffer) {
      completer.complete(buffer.toDart.asUint8List());
    });
  }).toJS;

  input.click();
  return completer.future;
}

/// Triggers a normal browser download of [bytes] as [filename].
void downloadBytes(Uint8List bytes, String filename) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/x-sqlite3'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
