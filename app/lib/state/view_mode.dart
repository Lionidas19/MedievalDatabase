/// Which of the three screens is on show.
///
/// In a file of its own, with no imports, because the tour needs to name the
/// screens and must not drag `AppController` in with them. `AppController`
/// reaches sqlite3 WASM, which will not load on the Dart VM, so importing it
/// anywhere the widget tests touch makes those widgets untestable: the test
/// fails to compile rather than fails an expectation, which is a confusing
/// way to find out. `preference_store` is split by platform for the same
/// reason.
///
/// `simple` is declared first because Advanced Search was the first screen
/// written. The navigation shows `advanced` first, which is why nothing may
/// index this enum for display order: see `_order` in `home_shell.dart`.
enum ViewMode { simple, advanced, guide }
