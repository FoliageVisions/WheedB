import 'dart:io';
import 'dart:math' show min;
import 'package:on_audio_query/on_audio_query.dart';
import '../models/song.dart';
import 'audio_metadata.dart';

/// Scans the device for audio files using on_audio_query and converts them
/// into the app's [Song] model. Also provides smart-playlist filtering.
class DeviceMusicScanner {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Request storage permission. Returns true if granted.
  Future<bool> requestPermission() async {
    return await _audioQuery.permissionsRequest();
  }

  /// Query all songs on the device and map them to [Song] objects.
  Future<List<Song>> scanAllSongs() async {
    final List<SongModel> deviceSongs = await _audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    return deviceSongs
        .where((s) => (s.duration ?? 0) > 0) // skip zero-length entries
        .map(_mapToSong)
        .toList();
  }

  /// Convert an on_audio_query [SongModel] into our [Song].
  Song _mapToSong(SongModel s) {
    final fileName = s.displayNameWOExt;
    final ext = s.fileExtension;
    final fullName = '$fileName.$ext';

    final isLosslessExt = const ['flac', 'alac', 'wav', 'aiff']
        .contains(ext.toLowerCase());

    int sampleRate = isLosslessExt ? 48000 : 44100;
    int bitDepth = isLosslessExt ? 24 : 16;

    // Parse real sample rate & bit depth from file header when possible.
    final data = s.data;
    if (data.isNotEmpty) {
      try {
        final file = File(data);
        if (file.existsSync()) {
          final raf = file.openSync(mode: FileMode.read);
          final hdr = raf.readSync(min(8192, file.lengthSync()));
          raf.closeSync();
          final meta = AudioMetadataParser.parse(hdr, fullName,
              fileSize: file.lengthSync());
          sampleRate = meta.sampleRateHz;
          bitDepth = meta.bitDepth;
        }
      } catch (_) {
        // Keep defaults on failure.
      }
    }

    return Song(
      id: s.id,
      title: s.title,
      artist: s.artist ?? 'Unknown Artist',
      album: s.album ?? 'Unknown Album',
      fileName: fullName,
      filePath: s.uri,
      duration: Duration(milliseconds: s.duration ?? 0),
      dateAdded: s.dateAdded != null
          ? DateTime.fromMillisecondsSinceEpoch(s.dateAdded! * 1000)
          : DateTime.now(),
      sampleRateHz: sampleRate,
      bitDepth: bitDepth,
    );
  }

  /// Filter for high-quality (FLAC / lossless / Hi-Res) songs.
  List<Song> filterHighQuality(List<Song> songs) {
    return songs.where((s) => s.isHighQuality).toList();
  }

  /// Filter for recently added songs (last 14 days).
  List<Song> filterRecentlyAdded(List<Song> songs) {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    return songs
        .where((s) => s.dateAdded.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
  }
}
