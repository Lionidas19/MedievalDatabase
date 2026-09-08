import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';
import '../services/database_repository.dart';
import '../services/file_io.dart';
import '../services/local_store.dart';
import '../services/sqlite_service.dart';

enum ViewMode { simple, advanced }

/// How the working copy is doing in private browser storage.
enum LocalSaveState {
  /// The browser gives us no private storage, so edits last only this visit.
  unsupported,

  /// Nothing to save — no edits since the last write.
  idle,

  /// A write is in flight.
  saving,

  /// Everything is written.
  saved,

  /// The last write failed; [AppController.saveError] says why.
  failed,
}

const _bundledAssetPath = 'data/1270s80sDatabase_normalized.sqlite';
const _bundledAssetFileName = '1270s80sDatabase_normalized.sqlite';

/// Central app state.
///
/// Three layers of storage, deliberately distinct:
///
///  * the database bundled with the app — always available, never written to;
///  * a working copy kept in private browser storage, which survives a reload
///    and is written automatically after every edit;
///  * downloaded `.sqlite` files, the only copies the user can keep, move or
///    send to somebody else.
///
/// The middle layer is a safety net, not a filing system: it is invisible to
/// the user's file manager and lives only in this browser, on this machine.
/// The app says so rather than letting anyone assume their work is filed
/// somewhere they could go and find.
class AppController extends ChangeNotifier {
  AppController() {
    _bootstrap();
  }

  String? _currentFileName;
  SqliteService? _sqliteService;
  DatabaseRepository? _repository;

  List<PriceEntry> _entries = [];
  bool _loading = false;
  bool _dirty = false;
  String? _error;
  ViewMode _mode = ViewMode.advanced;

  Timer? _saveDebounce;
  LocalSaveState _saveState = LocalSaveState.idle;
  DateTime? _lastSavedAt;
  String? _saveError;
  bool _restoredFromLocal = false;
  int _revision = 0;

  bool get hasData => _repository != null;

  /// Bumped whenever the entry list changes in a way that invalidates anything
  /// derived from it.
  ///
  /// The Explorer filters, prices and sorts 7,800 entries; doing that on every
  /// rebuild meant redoing it each time the save indicator ticked from
  /// 'Saving...' to 'Saved'. This is the cheap half of the fix — a number the
  /// view can compare against to know whether its cached result still stands.
  int get revision => _revision;
  String? get currentFileName => _currentFileName;
  List<PriceEntry> get entries => _entries;
  bool get isLoading => _loading;

  /// True when there are edits that have not been downloaded as a file. The
  /// working copy may still be safely saved in the browser — see [saveState].
  bool get isDirty => _dirty;
  String? get error => _error;
  ViewMode get mode => _mode;
  DatabaseRepository get repository => _repository!;

  LocalSaveState get saveState => _saveState;
  DateTime? get lastSavedAt => _lastSavedAt;
  String? get saveError => _saveError;

  /// True when this session picked up where a previous one left off.
  bool get restoredFromLocal => _restoredFromLocal;

  void setMode(ViewMode m) {
    _mode = m;
    notifyListeners();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _sqliteService?.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- loading --

  Future<void> _bootstrap() async {
    _loading = true;
    notifyListeners();

    if (!isLocalStoreSupported) {
      _saveState = LocalSaveState.unsupported;
    }

    final saved = await readLocalDatabase();
    if (saved != null) {
      try {
        await _replaceDatabase(saved, 'your saved copy');
        _restoredFromLocal = true;
        _saveState = isLocalStoreSupported
            ? LocalSaveState.saved
            : LocalSaveState.unsupported;
        return;
      } catch (e) {
        // A saved copy we cannot open is worse than none: fall back to the
        // bundled database rather than leaving the app with nothing, and say
        // what happened instead of silently discarding someone's work.
        debugPrint('saved database would not open: $e');
        _error = 'Your saved copy could not be opened, so the bundled '
            'database was loaded instead. The saved copy has been left alone — '
            'download a file before editing if you want to be safe.';
      }
    }

    await _loadBundledAsset(preserveError: _error != null);
  }

  Future<void> _loadBundledAsset({bool preserveError = false}) async {
    _loading = true;
    notifyListeners();
    try {
      final data = await rootBundle.load(_bundledAssetPath);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await _replaceDatabase(bytes, _bundledAssetFileName);
      if (!preserveError) _error = null;
    } catch (e) {
      _error = 'Could not load the bundled database: $e';
      _loading = false;
      notifyListeners();
    }
  }

  /// Discards the working copy and starts again from the database bundled with
  /// the app, forgetting what this browser had saved.
  Future<void> resetToBundledDefault() async {
    _saveDebounce?.cancel();
    await clearLocalDatabase();
    _restoredFromLocal = false;
    _error = null;
    await _loadBundledAsset();
    _saveState = isLocalStoreSupported
        ? LocalSaveState.idle
        : LocalSaveState.unsupported;
    notifyListeners();
  }

  /// Opens a `.sqlite` file the user picks from their device and makes it the
  /// new working copy. Returns false if the picker was cancelled.
  Future<bool> openFileFromDevice() async {
    try {
      _error = null;
      final bytes = await pickFileBytes();
      if (bytes == null) return false;
      _loading = true;
      notifyListeners();
      await _replaceDatabase(bytes, 'uploaded file');
      _restoredFromLocal = false;
      await _persistNow();
      return true;
    } catch (e) {
      _error = 'Could not open that file: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _replaceDatabase(Uint8List bytes, String fileName) async {
    _sqliteService?.dispose();
    _sqliteService = await SqliteService.openFromBytes(bytes);
    _repository = DatabaseRepository(_sqliteService!);
    final rawCount = _repository!.totalEntryCount;
    try {
      _entries = _repository!.loadAllEntries();
      _error = null;
    } catch (e, st) {
      _entries = [];
      _error = 'loadAllEntries() failed (raw row count in db: $rawCount): $e';
      debugPrint('$_error\n$st');
    }
    if (_entries.isEmpty && rawCount > 0 && _error == null) {
      _error = 'loadAllEntries() returned 0 rows but the database has '
          '$rawCount — likely a query/driver bug, not a data problem.';
    }
    _currentFileName = fileName;
    _dirty = false;
    _loading = false;
    _revision++;
    notifyListeners();
  }

  // ---------------------------------------------------------------- saving --

  /// Writes the working copy to private browser storage shortly after the last
  /// edit. Debounced because a save copies the whole database, and an editor
  /// typing into a field produces a change per keystroke.
  void _scheduleLocalSave() {
    if (!isLocalStoreSupported) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 900), _persistNow);
  }

  Future<void> _persistNow() async {
    final svc = _sqliteService;
    if (svc == null || !isLocalStoreSupported) return;
    _saveState = LocalSaveState.saving;
    _saveError = null;
    notifyListeners();
    try {
      await writeLocalDatabase(svc.exportBytes());
      _saveState = LocalSaveState.saved;
      _lastSavedAt = DateTime.now();
    } catch (e) {
      _saveState = LocalSaveState.failed;
      _saveError = '$e';
      debugPrint('could not save working copy: $e');
    }
    notifyListeners();
  }

  /// Forces a save now rather than waiting for the debounce.
  Future<void> saveNow() async {
    _saveDebounce?.cancel();
    await _persistNow();
  }

  // --------------------------------------------------------------- editing --

  /// Applies an edited entry to both the live database and the list the UI is
  /// showing.
  void applyEdit(PriceEntry updated) {
    repository.saveEntry(updated);
    final idx = _entries.indexWhere((e) => e.entryId == updated.entryId);
    if (idx != -1) {
      // Re-read rather than trusting the in-memory object: saving resolves
      // free-typed names into lookup rows, and the reloaded entry carries the
      // metric values those rows actually have.
      _entries[idx] = repository.loadEntry(updated.entryId) ?? updated;
    }
    _dirty = true;
    _revision++;
    notifyListeners();
    _scheduleLocalSave();
  }

  /// Creates a blank entry, adds it to the list and returns it.
  PriceEntry createEntry() {
    final id = repository.createEntry();
    final entry = repository.loadEntry(id)!;
    _entries.add(entry);
    _dirty = true;
    _revision++;
    notifyListeners();
    _scheduleLocalSave();
    return entry;
  }

  /// Deletes an entry, returning it so the caller can offer an undo.
  PriceEntry? deleteEntry(String entryId) {
    final idx = _entries.indexWhere((e) => e.entryId == entryId);
    if (idx == -1) return null;
    final removed = _entries.removeAt(idx);
    repository.deleteEntry(entryId);
    _dirty = true;
    _revision++;
    notifyListeners();
    _scheduleLocalSave();
    return removed;
  }

  // ----------------------------------------------------------- downloading --

  String _baseFileName(String name) {
    var base = name.replaceAll(RegExp(r'\.sqlite$', caseSensitive: false), '');
    base = base.replaceAll(RegExp(r'_\d{8}_\d{6}$'), '');
    // 'your saved copy' and 'uploaded file' are labels, not filenames.
    if (base.contains(' ')) base = 'database';
    return base;
  }

  String _timestamp() {
    final n = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${p2(n.month)}${p2(n.day)}_'
        '${p2(n.hour)}${p2(n.minute)}${p2(n.second)}';
  }

  /// Downloads the working copy as a new timestamped file, which is the only
  /// form of it the user can keep or pass on.
  String downloadCurrentFile() {
    final svc = _sqliteService!;
    final base = _baseFileName(_currentFileName ?? 'database');
    final newName = '${base}_${_timestamp()}.sqlite';
    downloadBytes(svc.exportBytes(), newName);
    _dirty = false;
    notifyListeners();
    return newName;
  }
}
