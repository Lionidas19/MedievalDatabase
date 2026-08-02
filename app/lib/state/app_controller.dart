import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';
import '../services/database_repository.dart';
import '../services/file_io.dart';
import '../services/sqlite_service.dart';

enum ViewMode { simple, advanced }

const _bundledAssetPath = 'data/1270s80sDatabase_normalized.sqlite';
const _bundledAssetFileName = '1270s80sDatabase_normalized.sqlite';

/// Central app state. The database bundled in the app (app/data/) is always
/// the base and the fallback — it loads automatically on startup, no click
/// required. Editing works directly against the in-memory copy; "downloading"
/// exports the current state as a file the user can keep, and "opening a
/// file" loads a previously-downloaded (or otherwise supplied) file back in
/// as the new basis to keep editing from.
class AppController extends ChangeNotifier {
  AppController() {
    _loadBundledAsset();
  }

  String? _currentFileName;
  SqliteService? _sqliteService;
  DatabaseRepository? _repository;

  List<PriceEntry> _entries = [];
  bool _loading = false;
  bool _dirty = false;
  String? _error;
  ViewMode _mode = ViewMode.advanced;

  bool get hasData => _repository != null;
  String? get currentFileName => _currentFileName;
  List<PriceEntry> get entries => _entries;
  bool get isLoading => _loading;
  bool get isDirty => _dirty;
  String? get error => _error;
  ViewMode get mode => _mode;
  DatabaseRepository get repository => _repository!;

  void setMode(ViewMode m) {
    _mode = m;
    notifyListeners();
  }

  Future<void> _loadBundledAsset() async {
    _loading = true;
    notifyListeners();
    try {
      final data = await rootBundle.load(_bundledAssetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await _replaceDatabase(bytes, _bundledAssetFileName);
      _error = null;
    } catch (e) {
      _error = 'Could not load the bundled database: $e';
      _loading = false;
      notifyListeners();
    }
  }

  /// Resets back to the database bundled with the app, discarding any
  /// in-memory edits that haven't been downloaded.
  Future<void> resetToBundledDefault() => _loadBundledAsset();

  /// Opens a `.sqlite` file the user picks from their device (e.g. one they
  /// downloaded earlier) and makes it the new basis for editing. Returns
  /// true if a file was actually opened (false if the picker was cancelled).
  Future<bool> openFileFromDevice() async {
    try {
      _error = null;
      final bytes = await pickFileBytes();
      if (bytes == null) return false;
      _loading = true;
      notifyListeners();
      await _replaceDatabase(bytes, 'uploaded file');
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
      _error = 'loadAllEntries() returned 0 rows but the database has $rawCount — '
          'likely a query/driver bug, not a data problem.';
    }
    _currentFileName = fileName;
    _dirty = false;
    _loading = false;
    notifyListeners();
  }

  /// Applies an edited entry both to the live sqlite database and to the
  /// in-memory list the UI is showing.
  void applyEdit(PriceEntry updated) {
    repository.saveEntry(updated);
    final idx = _entries.indexWhere((e) => e.entryId == updated.entryId);
    if (idx != -1) _entries[idx] = updated;
    _dirty = true;
    notifyListeners();
  }

  String _baseFileName(String name) {
    var base = name.replaceAll(RegExp(r'\.sqlite$', caseSensitive: false), '');
    base = base.replaceAll(RegExp(r'_\d{8}_\d{6}$'), '');
    return base;
  }

  String _timestamp() {
    final n = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${p2(n.month)}${p2(n.day)}_${p2(n.hour)}${p2(n.minute)}${p2(n.second)}';
  }

  /// Downloads the current (edited) database to the user's device as a new
  /// timestamped file. That downloaded file can later be re-opened via
  /// [openFileFromDevice] to keep editing from where this session left off.
  String downloadCurrentFile() {
    final svc = _sqliteService!;
    final base = _baseFileName(_currentFileName ?? 'database');
    final newName = '${base}_${_timestamp()}.sqlite';
    downloadBytes(svc.exportBytes(), newName);
    _currentFileName = newName;
    _dirty = false;
    notifyListeners();
    return newName;
  }
}
