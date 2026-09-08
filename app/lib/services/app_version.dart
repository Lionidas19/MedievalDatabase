import 'package:flutter/services.dart' show rootBundle;

/// The application's version, read from the bundled `pubspec.yaml`.
///
/// Read from the file rather than copied into a constant here. A constant is a
/// second place for the number to live, and the two drift apart the first time
/// somebody bumps one and forgets the other — at which point the version in
/// the corner is worse than none at all, because it is believed. `pubspec.yaml`
/// is declared as an asset for this and arrives down the same `rootBundle`
/// path as the database, so it needs no network and works under `flutter test`
/// as well as in the browser.
class AppVersion {
  AppVersion._();

  /// Resolved once, not per build. The rail rebuilds whenever the view
  /// changes, and a bundle read each time would be work for an answer that
  /// cannot have changed.
  static final Future<String> version = _read();

  /// `version: 0.0.1+1` → `v0.0.1`.
  ///
  /// Anchored to the start of a line, because the generated pubspec's comments
  /// say the word "version" a dozen times before the real one. The build
  /// number after the `+` is dropped: it means nothing to a reader, and this
  /// is a label rather than a diagnostic.
  static final _pattern = RegExp(r'^version:\s*([^\s+]+)', multiLine: true);

  static Future<String> _read() async {
    try {
      final match = _pattern.firstMatch(
        await rootBundle.loadString('pubspec.yaml'),
      );
      final found = match?.group(1);
      return found == null ? '' : 'v$found';
    } catch (_) {
      // Showing nothing is the right failure. A missing asset should cost the
      // corner of the navigation rail, not the app.
      return '';
    }
  }
}
