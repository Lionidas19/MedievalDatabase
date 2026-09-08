/// Offering to install the app, from inside the app.
///
/// Chrome and Edge put an install control in the address bar, which a reader
/// who has never installed a web app will not recognise and will not look for.
/// The browser hands the page the offer instead — a `beforeinstallprompt`
/// event — and that is what this exposes, so the invitation can sit in the
/// app's own menu where somebody might actually find it.
///
/// Split by platform for the same reason as `preference_store.dart`: the Dart
/// VM that runs `flutter test` has no `package:web`, and a widget that could
/// not be loaded there would take the whole widget tree's tests with it.
library;

export 'install_prompt_vm.dart'
    if (dart.library.js_interop) 'install_prompt_web.dart';
