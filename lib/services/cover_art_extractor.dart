import 'dart:io';
import 'dart:typed_data';

import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Extracts embedded cover art from audio files and persists it to disk.
class CoverArtExtractor {
  CoverArtExtractor._();
  static final CoverArtExtractor instance = CoverArtExtractor._();

  final _audioQuery = OnAudioQuery();

  /// Attempts to extract high-resolution artwork from the first song in
  /// [filePaths] that has embedded art.
  ///
  /// Returns the saved image's absolute path, or `null` if no art was found.
  ///
  /// [collectionId] – a unique identifier (e.g. playlist/album DB id) used to
  /// name the output file so each collection gets its own cover.
  Future<String?> extractAndSave({
    required List<String> filePaths,
    required int collectionId,
    required String collectionType,
  }) async {
    for (final filePath in filePaths) {
      final art = await _tryExtract(filePath);
      if (art != null && art.isNotEmpty) {
        return _saveToDisk(
          art,
          collectionId: collectionId,
          collectionType: collectionType,
        );
      }
    }
    return null;
  }

  /// Tries to find the song in MediaStore by matching the display name,
  /// then fetches its embedded artwork bytes.
  Future<Uint8List?> _tryExtract(String filePath) async {
    try {
      final displayName = p.basename(filePath);
      final nameWithoutExt = p.basenameWithoutExtension(filePath);

      // Search by title in the MediaStore.
      final results = await _audioQuery.queryWithFilters(
        nameWithoutExt,
        WithFiltersType.AUDIOS,
      );

      if (results.isEmpty) return null;

      // Convert to SongModel and find the best match.
      final songs = results.map((e) => SongModel(e as Map)).toList();
      final match = songs.cast<SongModel?>().firstWhere(
            (s) => s!.displayName == displayName,
            orElse: () => songs.isNotEmpty ? songs.first : null,
          );

      if (match == null) return null;

      return _audioQuery.queryArtwork(
        match.id,
        ArtworkType.AUDIO,
        quality: 100,
        size: 800,
      );
    } catch (_) {
      return null;
    }
  }

  /// Persists raw image bytes to the app's documents directory.
  /// Returns the absolute path where the image was written.
  Future<String> _saveToDisk(
    Uint8List bytes, {
    required int collectionId,
    required String collectionType,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final coverDir = Directory(p.join(dir.path, 'cover_art'));
    if (!await coverDir.exists()) {
      await coverDir.create(recursive: true);
    }

    final file = File(
      p.join(coverDir.path, '${collectionType}_$collectionId.jpg'),
    );
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
