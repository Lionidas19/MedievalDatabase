import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
import 'package:typed_data/typed_buffers.dart';

/// Wraps a single opened sqlite3 database backed by an in-memory virtual
/// file system, so we can hand it raw bytes on load and pull raw bytes back
/// out on save (there is no real disk under a web app).
class SqliteService {
  SqliteService._(this._sqlite3, this._vfs, this.db);

  final WasmSqlite3 _sqlite3;
  final InMemoryFileSystem _vfs;
  final CommonDatabase db;

  static const _dbPath = '/current.sqlite';
  static WasmSqlite3? _engine;

  static Future<WasmSqlite3> _loadEngine() async {
    return _engine ??= await WasmSqlite3.loadFromUrlString('sqlite3.wasm');
  }

  static Future<SqliteService> openFromBytes(Uint8List bytes) async {
    final sqlite3 = await _loadEngine();
    final vfs = InMemoryFileSystem();
    vfs.fileData[_dbPath] = Uint8Buffer()..addAll(bytes);
    sqlite3.registerVirtualFileSystem(vfs, makeDefault: true);
    final db = sqlite3.open(_dbPath, vfs: vfs.name);
    db.execute('PRAGMA foreign_keys = ON');
    return SqliteService._(sqlite3, vfs, db);
  }

  /// Exports the current (possibly edited) database as bytes, suitable for
  /// writing to a new file.
  Uint8List exportBytes() {
    final buffer = _vfs.fileData[_dbPath];
    if (buffer == null) return Uint8List(0);
    return buffer.buffer.asUint8List(0, buffer.length);
  }

  void dispose() {
    db.close();
    _sqlite3.unregisterVirtualFileSystem(_vfs);
  }
}
