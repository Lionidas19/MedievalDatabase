/// Preferences in the browser's `localStorage`.
///
/// Every access is guarded: private-browsing modes and locked-down browsers
/// throw on `localStorage` rather than returning null, and an unreadable
/// preference should mean "use the default", never a blank screen.
library;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

const _prefix = 'priceExplorer.';

String? readPreference(String key) {
  try {
    return web.window.localStorage.getItem('$_prefix$key');
  } catch (e) {
    debugPrint('could not read preference $key: $e');
    return null;
  }
}

void writePreference(String key, String value) {
  try {
    web.window.localStorage.setItem('$_prefix$key', value);
  } catch (e) {
    debugPrint('could not save preference $key: $e');
  }
}
