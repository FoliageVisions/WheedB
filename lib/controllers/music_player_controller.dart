import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';

/// Production music-player controller backed by just_audio + audio_service.
///
/// Maintains the same public API surface as the old simulated
/// PlaybackController so all existing UI widgets work unchanged.
class MusicPlayerController extends ChangeNotifier {
  AudioPlayer? _player;
  WheedBAudioHandler? _handler;
  bool _initialised = false;

  List<Song> _queue = [];
  int _currentIndex = -1;

  // ── Back-button double-press detection ──
  DateTime? _lastBackPress;
  static const _doublePressWindow = Duration(milliseconds: 1500);

  // ── Streams we subscribe to ──
  final List<StreamSubscription<dynamic>> _subs = [];

  // ── Cached state from streams ──
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;

  // ── Audio metadata stream ──
  final _audioInfoController = StreamController<AudioInfo>.broadcast();
  Stream<AudioInfo> get audioInfoStream => _audioInfoController.stream;

  // ── Public getters (same shape as old PlaybackController) ──
  Song? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get remaining =>
      _duration > _position ? _duration - _position : Duration.zero;
  bool get hasQueue => _queue.isNotEmpty;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get loopMode => _loopMode;

  AudioPlayer? get player => _player;

  /// Must be called once before any playback.
  Future<void> init() async {
    if (_initialised) return;

    _player = AudioPlayer();

    _handler = await AudioService.init<WheedBAudioHandler>(
      builder: () => WheedBAudioHandler(_player!),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.wheedb.audio',
        androidNotificationChannelName: 'WheedB Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );

    // Position stream → update _position + notify UI.
    _subs.add(_player!.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    }));

    // Duration stream → update _duration.
    _subs.add(_player!.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    }));

    // Playing state.
    _subs.add(_player!.playingStream.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    }));

    // Current index changes (e.g. auto-advance).
    _subs.add(_player!.currentIndexStream.listen((idx) {
      if (idx != null && idx != _currentIndex && idx < _queue.length) {
        _currentIndex = idx;
        _emitAudioInfo();
        notifyListeners();
      }
    }));

    // When a track completes and we aren't looping, just_audio handles the
    // advance via ConcatenatingAudioSource; we listen for the sequence change.
    _subs.add(_player!.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        notifyListeners();
      }
    }));

    _initialised = true;
  }

  // ── Queue management ──

  Future<void> loadQueue(List<Song> songs, {int startIndex = 0}) async {
    if (_player == null) return;
    _queue = List.of(songs);
    _currentIndex = startIndex.clamp(0, _queue.length - 1);

    // Build a concatenating source for gapless transitions.
    final sources = songs.map((s) {
      final tag = MediaItem(
        id: s.fileName,
        title: s.title,
        artist: s.artist,
        album: s.album,
        duration: s.duration,
      );

      // Web imports carry in-memory bytes; mobile imports carry file paths.
      if (s.audioBytes != null) {
        return _BytesAudioSource(s.audioBytes!, tag: tag);
      }

      // For device files the fileName is an absolute path or content URI.
      // AudioSource.uri handles both "file://" and "content://" schemes.
      final uri = s.filePath != null
          ? Uri.parse(s.filePath!)
          : Uri.file(s.fileName);
      return AudioSource.uri(uri, tag: tag);
    }).toList();

    await _player!.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: _currentIndex,
      initialPosition: Duration.zero,
    );

    _emitAudioInfo();
    notifyListeners();
  }

  // ── Transport controls ──

  Future<void> togglePlayPause() async {
    if (currentSong == null || _player == null) return;
    _isPlaying ? await _player!.pause() : await _player!.play();
  }

  Future<void> seekTo(Duration target) async {
    if (_player == null) return;
    Duration clamped;
    if (target < Duration.zero) {
      clamped = Duration.zero;
    } else if (target > _duration) {
      clamped = _duration;
    } else {
      clamped = target;
    }
    await _player!.seek(clamped);
  }

  /// Dual-logic back button:
  /// Single press → reset to 0:00.
  /// Double press within 1.5 s → skip to previous track.
  Future<void> handleBack() async {
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) <= _doublePressWindow) {
      _lastBackPress = null;
      await skipPrevious();
    } else {
      _lastBackPress = now;
      await seekTo(Duration.zero);
    }
  }

  Future<void> skipPrevious() async {
    if (_queue.isEmpty || _player == null) return;
    final newIndex =
        (_currentIndex - 1 < 0) ? _queue.length - 1 : _currentIndex - 1;
    await _player!.seek(Duration.zero, index: newIndex);
    _currentIndex = newIndex;
    _emitAudioInfo();
    notifyListeners();
  }

  Future<void> skipNext() async {
    if (_queue.isEmpty || _player == null) return;
    final newIndex = (_currentIndex + 1) % _queue.length;
    await _player!.seek(Duration.zero, index: newIndex);
    _currentIndex = newIndex;
    _emitAudioInfo();
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    if (_player == null) return;
    _shuffleEnabled = !_shuffleEnabled;
    await _player!.setShuffleModeEnabled(_shuffleEnabled);
    notifyListeners();
  }

  Future<void> cycleLoopMode() async {
    if (_player == null) return;
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
      case LoopMode.all:
        _loopMode = LoopMode.one;
      case LoopMode.one:
        _loopMode = LoopMode.off;
    }
    await _player!.setLoopMode(_loopMode);
    notifyListeners();
  }

  // ── Audio info stream ──

  void _emitAudioInfo() {
    final song = currentSong;
    if (song == null) return;
    _audioInfoController.add(AudioInfo(
      frequencyKHz: song.sampleRateHz / 1000.0,
      bitDepth: song.bitDepth,
      isLossless: song.isLossless,
      isHiRes: song.isHiRes,
    ));

    // Update the media item for lock-screen / notification display.
    _handler?.mediaItem.add(MediaItem(
      id: song.fileName,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
    ));
  }

  // ── Cleanup ──

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _audioInfoController.close();
    _player?.dispose();
    super.dispose();
  }
}

/// Value object emitted on [MusicPlayerController.audioInfoStream].
class AudioInfo {
  final double frequencyKHz;
  final int bitDepth;
  final bool isLossless;
  final bool isHiRes;

  const AudioInfo({
    required this.frequencyKHz,
    required this.bitDepth,
    required this.isLossless,
    required this.isHiRes,
  });

  /// e.g. "96 kHz/24-bit"
  String get label {
    final freqStr = frequencyKHz == frequencyKHz.roundToDouble()
        ? '${frequencyKHz.round()}'
        : frequencyKHz.toStringAsFixed(1);
    return '$freqStr kHz/$bitDepth-bit';
  }
}

/// A [StreamAudioSource] that serves audio from an in-memory [Uint8List].
/// Used for web imports where only bytes (not file paths) are available.
// ignore: subtype_of_sealed_class
class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;

  _BytesAudioSource(this._bytes, {super.tag});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final effectiveStart = start ?? 0;
    final effectiveEnd = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: effectiveEnd - effectiveStart,
      offset: effectiveStart,
      stream: Stream.value(
        _bytes.sublist(effectiveStart, effectiveEnd),
      ),
      contentType: 'audio/mpeg',
    );
  }
}
