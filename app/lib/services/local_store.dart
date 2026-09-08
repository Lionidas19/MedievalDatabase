/// Keeps the working database in the browser's Origin Private File System, so
/// edits survive a reload.
///
/// This is deliberately *not* the sqlite VFS. The live database runs on an
/// in-memory VFS — that is what makes exporting a downloadable copy possible —
/// and this file mirrors those bytes into private browser storage whenever
/// they change. The two roles are separate on purpose: one is a working file,
/// the other is a safety net.
///
/// OPFS is private to the origin and invisible in the user's file manager.
/// Downloading remains the way to get a copy you can keep, move or send.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const _fileName = 'working.sqlite';

/// Whether this browser gives us private storage at all.
///
/// Older Safari and Firefox in private-browsing mode do not, in which case the
/// app still works — it just cannot remember anything between visits, and says
/// so rather than pretending.
bool get isLocalStoreSupported {
  try {
    return web.window.navigator.storage.isDefinedAndNotNull;
  } catch (_) {
    return false;
  }
}

Future<web.FileSystemDirectoryHandle> _root() =>
    web.window.navigator.storage.getDirectory().toDart;

/// Reads the previously saved database, or null when there is nothing stored
/// yet or storage is unavailable.
Future<Uint8List?> readLocalDatabase() async {
  if (!isLocalStoreSupported) return null;
  try {
    final root = await _root();
    final handle = await root.getFileHandle(_fileName).toDart;
    final file = await handle.getFile().toDart;
    final buffer = await file.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();
    // A zero-length file means a write was interrupted. Treat it as absent
    // rather than handing sqlite something it cannot open.
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    // getFileHandle throws NotFoundError when nothing has been saved yet,
    // which is the ordinary first-run case and not worth surfacing.
    return null;
  }
}

/// Writes [bytes] as the saved database, replacing whatever was there.
Future<void> writeLocalDatabase(Uint8List bytes) async {
  if (!isLocalStoreSupported) return;
  final root = await _root();
  final handle = await root
      .getFileHandle(_fileName, web.FileSystemGetFileOptions(create: true))
      .toDart;
  final sink = await handle.createWritable().toDart;
  try {
    await sink.write(bytes.toJS).toDart;
  } finally {
    // The write only lands when the stream closes, so this must happen even
    // if writing threw — otherwise the previous contents stay half-replaced.
    await sink.close().toDart;
  }
}

/// Forgets the saved database, so the next load falls back to the bundled one.
Future<void> clearLocalDatabase() async {
  if (!isLocalStoreSupported) return;
  try {
    final root = await _root();
    await root.removeEntry(_fileName).toDart;
  } catch (_) {
    // Already absent.
  }
}

/// Roughly how much room the browser is willing to give this origin, and how
/// much is in use. Null when the browser will not say.
Future<({int used, int quota})?> localStorageUsage() async {
  if (!isLocalStoreSupported) return null;
  try {
    final estimate = await web.window.navigator.storage.estimate().toDart;
    return (used: estimate.usage, quota: estimate.quota);
  } catch (_) {
    return null;
  }
}
