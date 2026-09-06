/// Small key/value store for display preferences.
///
/// Deliberately separate from `local_store.dart`, which mirrors the whole
/// database into the browser's private file system. That machinery exists to
/// protect a reader's *edits*; a remembered theme does not need it. These
/// values go into ordinary `localStorage`, where they cost nothing and are
/// trivially cleared.
///
/// The implementation is chosen at compile time so that this file — and
/// therefore the theme, and therefore every widget — can still be loaded on
/// the Dart VM, where `flutter test` runs and `package:web` does not exist.
/// Without that split, adding a remembered setting would have quietly made the
/// entire widget tree untestable.
library;

export 'preference_store_vm.dart'
    if (dart.library.js_interop) 'preference_store_web.dart';
