import 'dart:js_interop';

/// Set up in `web/flutter_bootstrap.js`, which has to be listening before the
/// engine starts: `beforeinstallprompt` fires early, only once, and cannot be
/// asked for again afterwards.
@JS('pwaInstallAvailable')
external bool _available();

@JS('pwaInstallShow')
external JSPromise<JSAny?> _show();

/// Whether the browser has offered to install, and has not been taken up on it.
///
/// False in Firefox, which does not implement this, and in Safari, where
/// installing is a manual Share-menu affair. Also false once the app *is*
/// installed. The caller shows nothing in any of those cases rather than
/// offering something that would do nothing.
bool get canInstallApp {
  try {
    return _available();
  } catch (_) {
    // An older cached bootstrap without these functions. Not worth an error.
    return false;
  }
}

/// Hands the browser's own install dialog to the reader.
///
/// The offer is spent whether they accept or decline, which is the browser's
/// rule and not ours; [canInstallApp] goes false either way.
Future<void> promptToInstallApp() async {
  try {
    await _show().toDart;
  } catch (_) {
    // Declined, dismissed, or gone stale. Nothing to report either way.
  }
}
