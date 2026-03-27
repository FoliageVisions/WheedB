import 'package:on_audio_query/on_audio_query.dart';
import '../models/song.dart';

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

    // on_audio_query doesn't expose sample rate or bit depth directly,
    // so we infer defaults from the file extension when unavailable.
    final isLosslessExt = const ['flac', 'alac', 'wav', 'aiff']
        .contains(ext.toLowerCase());

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
      sampleRateHz: isLosslessExt ? 48000 : 44100,
      bitDepth: isLosslessExt ? 24 : 16,
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
