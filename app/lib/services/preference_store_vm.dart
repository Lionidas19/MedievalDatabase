/// Preferences off the web: there is nowhere to put them, and nothing asking.
///
/// Reached only by `flutter test` on the Dart VM. Reading always returns null,
/// so every setting falls back to its default — which is exactly what a test
/// wants, and means a test's own choices cannot leak into the next one.
library;

String? readPreference(String key) => null;

void writePreference(String key, String value) {}
