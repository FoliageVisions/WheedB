import 'dart:typed_data';

/// Import lifecycle state shown in the UI.
enum SongImportStatus { ready, importing, failed }

class Song {
  final int? id;
  final String title;
  final String artist;
  final String album;
  final String fileName;
  final String? filePath;
  final Duration duration;

  /// Raw audio bytes for web playback (null on mobile where filePath is used).
  final Uint8List? audioBytes;

  /// Date the song was added to the library.
  final DateTime dateAdded;

  /// Number of times the song has been played.
  final int playCount;

  /// Whether the user has marked this song as a favourite.
  final bool isFavorite;

  /// Sample rate in Hz (e.g. 44100, 48000, 96000).
  final int sampleRateHz;

  /// Bit depth (e.g. 16, 24, 32).
  final int bitDepth;

  /// Current import status (optimistic UI).
  final SongImportStatus importStatus;

  /// Pre-computed lowercase search key for fast filtering.
  late final String _searchKey;

  /// Whether this is a lossless / Hi-Res file.
  bool get isHighQuality {
    final lowerName = fileName.toLowerCase();
    return lowerName.endsWith('.flac') ||
        lowerName.endsWith('.alac') ||
        lowerName.endsWith('.wav') ||
        lowerName.endsWith('.aiff') ||
        sampleRateHz > 48000;
  }

  /// True for lossless containers (FLAC, ALAC, WAV, AIFF).
  bool get isLossless {
    final lowerName = fileName.toLowerCase();
    return lowerName.endsWith('.flac') ||
        lowerName.endsWith('.alac') ||
        lowerName.endsWith('.wav') ||
        lowerName.endsWith('.aiff');
  }

  /// True when the sample rate exceeds 48 kHz.
  bool get isHiRes => sampleRateHz > 48000;

  /// Formatted frequency string, e.g. "48 kHz/24-bit".
  String get audioInfoLabel {
    final freqKHz = sampleRateHz / 1000;
    // Show one decimal only when fractional (e.g. 44.1 kHz), else integer.
    final freqStr =
        freqKHz == freqKHz.roundToDouble() ? '${freqKHz.round()}' : freqKHz.toStringAsFixed(1);
    return '$freqStr kHz/$bitDepth-bit';
  }

  Song({
    this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.fileName,
    this.filePath,
    this.audioBytes,
    this.duration = Duration.zero,
    DateTime? dateAdded,
    this.playCount = 0,
    this.isFavorite = false,
    this.sampleRateHz = 44100,
    this.bitDepth = 16,
    this.importStatus = SongImportStatus.ready,
  }) : dateAdded = dateAdded ?? DateTime.now() {
    _searchKey = '$title\u0000$artist\u0000$album\u0000$fileName'.toLowerCase();
  }

  /// Returns true if this song matches the given lowercase query.
  bool matchesQuery(String lowercaseQuery) => _searchKey.contains(lowercaseQuery);

  Song copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    String? fileName,
    String? filePath,
    Uint8List? audioBytes,
    Duration? duration,
    DateTime? dateAdded,
    int? playCount,
    bool? isFavorite,
    int? sampleRateHz,
    int? bitDepth,
    SongImportStatus? importStatus,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      audioBytes: audioBytes ?? this.audioBytes,
      duration: duration ?? this.duration,
      dateAdded: dateAdded ?? this.dateAdded,
      playCount: playCount ?? this.playCount,
      isFavorite: isFavorite ?? this.isFavorite,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      bitDepth: bitDepth ?? this.bitDepth,
      importStatus: importStatus ?? this.importStatus,
    );
  }
}

/// Maintains a pre-built index over a list of songs for sub-50ms filtering.
class SongSearchIndex {
  final List<Song> _songs;

  SongSearchIndex(this._songs);

  List<Song> search(String query) {
    if (query.isEmpty) return _songs;
    final lq = query.toLowerCase();
    return _songs.where((s) => s.matchesQuery(lq)).toList(growable: false);
  }
}
