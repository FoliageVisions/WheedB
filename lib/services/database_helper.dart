import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/playlist.dart';
import '../models/song.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final newPath = join(dbPath, 'wheedb.db');

    // One-time migration: copy old yourtune.db → wheedb.db if it exists
    // and the new database hasn't been created yet.
    final oldPath = join(dbPath, 'yourtune.db');
    if (!File(newPath).existsSync() && File(oldPath).existsSync()) {
      debugPrint('[WheedB DB] Migrating yourtune.db → wheedb.db');
      await File(oldPath).copy(newPath);
    }

    return openDatabase(
      newPath,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        cover_art_path TEXT,
        is_manual_cover INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE albums (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        artist TEXT,
        cover_art_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE playlist_songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE playlist_songs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          playlist_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          artist TEXT NOT NULL,
          album TEXT NOT NULL,
          file_name TEXT NOT NULL,
          file_path TEXT,
          sort_order INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE playlists ADD COLUMN cover_art_path TEXT',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE playlists ADD COLUMN is_manual_cover INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  /// Inserts a new playlist or album row.
  /// Returns the auto-generated id.
  Future<int> saveNewContainer(String name, {required bool isPlaylist}) async {
    final db = await database;

    if (isPlaylist) {
      return db.insert('playlists', {
        'name': name,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      return db.insert('albums', {
        'name': name,
      });
    }
  }

  /// Returns all manual (user-created) playlists with their songs.
  Future<List<Playlist>> loadPlaylists() async {
    final db = await database;
    final rows = await db.query('playlists', orderBy: 'created_at DESC');

    final playlists = <Playlist>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final songRows = await db.query(
        'playlist_songs',
        where: 'playlist_id = ?',
        whereArgs: [id],
        orderBy: 'sort_order ASC',
      );

      final songs = songRows
          .map((s) => Song(
                title: s['title'] as String,
                artist: s['artist'] as String,
                album: s['album'] as String,
                fileName: s['file_name'] as String,
                filePath: s['file_path'] as String?,
              ))
          .toList();

      playlists.add(Playlist(
        id: id,
        name: row['name'] as String,
        icon: Icons.playlist_play_rounded,
        songs: songs,
        coverArtPath: row['cover_art_path'] as String?,
        isManualCover: (row['is_manual_cover'] as int?) == 1,
      ));
    }
    return playlists;
  }

  /// Updates the cover art path for a playlist or album.
  /// Updates the cover art path for a playlist or album.
  /// When [isManual] is true a flag is stored so auto-extraction won't
  /// overwrite the user's choice.
  Future<void> updateCoverArt({
    required int id,
    required bool isPlaylist,
    required String path,
    bool isManual = false,
  }) async {
    final db = await database;
    final table = isPlaylist ? 'playlists' : 'albums';
    final values = <String, Object?>{'cover_art_path': path};
    if (isPlaylist) {
      values['is_manual_cover'] = isManual ? 1 : 0;
    }
    await db.update(table, values, where: 'id = ?', whereArgs: [id]);
  }

  /// Adds songs to a playlist.
  Future<void> addSongsToPlaylist(int playlistId, List<Song> songs) async {
    final db = await database;
    final batch = db.batch();

    // Get current max sort_order for this playlist.
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM playlist_songs WHERE playlist_id = ?',
      [playlistId],
    );
    var order = (result.first['max_order'] as int) + 1;

    for (final song in songs) {
      batch.insert('playlist_songs', {
        'playlist_id': playlistId,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'file_name': song.fileName,
        'file_path': song.filePath,
        'sort_order': order++,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Returns all user-created albums as raw maps.
  Future<List<Map<String, dynamic>>> loadAlbums() async {
    final db = await database;
    return db.query('albums', orderBy: 'name ASC');
  }

  /// Renames a playlist or album.
  Future<void> renameContainer(
    int id,
    String newName, {
    required bool isPlaylist,
  }) async {
    final db = await database;
    final table = isPlaylist ? 'playlists' : 'albums';
    await db.update(table, {'name': newName}, where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes a playlist or album (cascade removes playlist_songs).
  Future<void> deleteContainer(int id, {required bool isPlaylist}) async {
    final db = await database;
    final table = isPlaylist ? 'playlists' : 'albums';
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}
