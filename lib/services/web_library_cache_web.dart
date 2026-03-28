import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../models/song.dart';

/// Persists song library metadata to IndexedDB on web platforms.
class WebLibraryCache {
  static final instance = WebLibraryCache._();
  WebLibraryCache._();

  static const _dbName = 'wheedb_library';
  static const _dbVersion = 1;
  static const _songStore = 'songs';

  web.IDBDatabase? _db;

  // ── Open / create database ───────────────────────────────────────

  Future<web.IDBDatabase> _open() async {
    if (_db != null) return _db!;

    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, _dbVersion);

    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_songStore)) {
        db.createObjectStore(
          _songStore,
          web.IDBObjectStoreParameters(keyPath: 'fileName'.toJS),
        );
      }
    }).toJS;

    request.onsuccess = ((web.Event _) {
      _db = request.result as web.IDBDatabase;
      completer.complete(_db!);
    }).toJS;

    request.onerror = ((web.Event _) {
      completer.completeError('Failed to open IndexedDB');
    }).toJS;

    return completer.future;
  }

  /// Wraps an [IDBRequest] in a [Future] that resolves with the result.
  Future<JSAny?> _complete(web.IDBRequest request) {
    final c = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => c.complete(request.result)).toJS;
    request.onerror =
        ((web.Event _) => c.completeError(request.error?.message ?? 'IDB error')).toJS;
    return c.future;
  }

  // ── Read ─────────────────────────────────────────────────────────

  /// Loads all cached song metadata from IndexedDB.
  Future<List<Song>> loadSongs() async {
    try {
      final db = await _open();
      final txn = db.transaction(_songStore.toJS, 'readonly');
      final store = txn.objectStore(_songStore);
      final result = await _complete(store.getAll());

      if (result == null) return [];

      final list = (result.dartify() ?? <dynamic>[]) as List;
      return [
        for (final item in list)
          _songFromMap(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (e) {
      // IndexedDB unavailable or corrupt — degrade gracefully.
      return [];
    }
  }

  // ── Write ────────────────────────────────────────────────────────

  /// Persists song metadata (upsert by fileName to prevent duplicates).
  Future<void> saveSongs(List<Song> songs) async {
    try {
      final db = await _open();
      final txn = db.transaction(_songStore.toJS, 'readwrite');
      final store = txn.objectStore(_songStore);

      for (final song in songs) {
        store.put(_songToJS(song));
      }

      // Wait for transaction to complete.
      final done = Completer<void>();
      txn.oncomplete = ((web.Event _) => done.complete()).toJS;
      txn.onerror = ((web.Event _) => done.completeError('write failed')).toJS;
      await done.future;
    } catch (_) {
      // Best-effort — silent fail keeps the app working.
    }
  }

  // ── Serialisation helpers ────────────────────────────────────────

  JSAny _songToJS(Song s) => <String, Object>{
        'fileName': s.fileName,
        'title': s.title,
        'artist': s.artist,
        'album': s.album,
        'durationMs': s.duration.inMilliseconds,
        'isFavorite': s.isFavorite,
        'playCount': s.playCount,
        'sampleRateHz': s.sampleRateHz,
        'bitDepth': s.bitDepth,
        'dateAdded': s.dateAdded.toIso8601String(),
      }.jsify()!;

  Song _songFromMap(Map<String, dynamic> m) => Song(
        title: m['title'] as String? ?? '',
        artist: m['artist'] as String? ?? 'Unknown Artist',
        album: m['album'] as String? ?? 'Imported',
        fileName: m['fileName'] as String? ?? '',
        duration: Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
        isFavorite: m['isFavorite'] as bool? ?? false,
        playCount: (m['playCount'] as num?)?.toInt() ?? 0,
        sampleRateHz: (m['sampleRateHz'] as num?)?.toInt() ?? 44100,
        bitDepth: (m['bitDepth'] as num?)?.toInt() ?? 16,
        dateAdded: DateTime.tryParse(m['dateAdded'] as String? ?? '') ?? DateTime.now(),
      );
}
