import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';

/// Production music-player controller backed by just_audio + audio_service.
///
/// Single source of truth for playback state. All UI listens to this
/// ChangeNotifier — there is exactly ONE set of stream subscriptions
/// (created in [init]) and no duplicated state tracking.
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

  /// Monotonically increasing operation ID. Each [playTrack] call bumps
  /// this counter; stale async continuations compare their captured id
  /// against the current value and bail out if it no longer matches.
  /// This prevents two rapid taps from fighting over setAudioSource/play.
  int _playOpId = 0;

  /// When true, stream listeners won't overwrite optimistic state.
  /// Prevents the playingStream from flipping _isPlaying back to false
  /// during setAudioSource.
  bool _suppressStreams = false;

  // ── Public getters ──
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

    // AudioService uses native platform channels — skip on web.
    if (!kIsWeb) {
      _handler = await AudioService.init<WheedBAudioHandler>(
        builder: () => WheedBAudioHandler(_player!),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.wheedb.audio',
          androidNotificationChannelName: 'WheedB Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    }

    // Position stream → update _position + notify UI.
    _subs.add(_player!.positionStream.listen((pos) {
      if (_suppressStreams) return;
      _position = pos;
      notifyListeners();
    }));

    // Duration stream → update _duration.
    // Also re-emit the media item so the lock-screen progress bar
    // gets the real duration (imported files start with Duration.zero
    // until setAudioSource resolves the actual length).
    _subs.add(_player!.durationStream.listen((dur) {
      final newDur = dur ?? Duration.zero;
      if (newDur != _duration) {
        _duration = newDur;
        _updateMediaItem();
        notifyListeners();
      }
    }));

    // Playing state — the single source of truth for _isPlaying.
    // Suppressed during playTrack() to avoid overwriting optimistic state
    // with a transient false from setAudioSource.
    _subs.add(_player!.playingStream.listen((playing) {
      if (_suppressStreams) return;
      if (playing != _isPlaying) {
        _isPlaying = playing;
        notifyListeners();
      }
    }));

    // Current index changes (e.g. auto-advance at track boundary).
    // Suppressed during playTrack()/skip to avoid double-notification.
    _subs.add(_player!.currentIndexStream.listen((idx) {
      if (_suppressStreams) return;
      if (idx != null && idx != _currentIndex && idx < _queue.length) {
        _currentIndex = idx;
        _updateMediaItem();
        notifyListeners();
      }
    }));

    // When the entire queue finishes (no loop), transition to stopped.
    _subs.add(_player!.processingStateStream.listen((state) {
      if (_suppressStreams) return;
      if (state == ProcessingState.completed) {
        // The queue has ended. Update our state so UI shows paused.
        // playingStream will also fire false, but we gate on != to
        // avoid a redundant second notifyListeners().
        if (_isPlaying) {
          _isPlaying = false;
          notifyListeners();
        }
      }
    }));

    _initialised = true;
  }

  // ── Queue management ──

  /// Identity of the currently loaded audio source (fileNames in order).
  /// Used to skip expensive [setAudioSource] rebuilds when the same
  /// queue is tapped again at a different index.
  List<String> _loadedQueueIds = [];

  /// Play a specific track. Reuses the loaded audio source when the
  /// queue hasn't changed, and updates UI state optimistically before
  /// any async work so the "playing" indicator appears instantly.
  ///
  /// Safe against rapid taps: each call bumps [_playOpId]; stale
  /// continuations detect the mismatch and bail out.
  Future<void> playTrack(List<Song> songs, {required int index}) async {
    if (_player == null) return;

    final clampedIndex = index.clamp(0, songs.length - 1);

    // Bump the operation counter — any in-flight playTrack() with an
    // older id will see the mismatch after its awaits and bail out.
    final opId = ++_playOpId;

    // ── Optimistic state: update UI before any I/O ──
    _queue = List.of(songs);
    _currentIndex = clampedIndex;
    _isPlaying = true;
    _position = Duration.zero;
    _updateMediaItem();
    _updateQueue();
    notifyListeners();

    // Suppress stream listeners so they don't overwrite our optimistic
    // state with transient values during setAudioSource / seek.
    _suppressStreams = true;

    try {
      // ── Fast path: same queue → seek to new index only ──
      if (_matchesLoadedQueue(songs)) {
        await _player!.seek(Duration.zero, index: clampedIndex);
        if (opId != _playOpId) { _suppressStreams = false; return; }
        _suppressStreams = false;
        if (!_player!.playing) await _player!.play();
        return;
      }

      // ── Build the full queue upfront so the player never needs to
      // mutate a ConcatenatingAudioSource during active playback
      // (which causes audible clicks / pops on Android & iOS). ──
      _loadedQueueIds = songs.map((s) => s.fileName).toList();

      final sources = songs.map(_buildSource).toList();

      await _player!.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: clampedIndex,
        initialPosition: Duration.zero,
      );

      if (opId != _playOpId) { _suppressStreams = false; return; }
      _suppressStreams = false;
      await _player!.play();
    } catch (e) {
      debugPrint('[WheedB] playTrack error: $e');
      if (opId == _playOpId) {
        _suppressStreams = false;
        _isPlaying = false;
        notifyListeners();
      }
    }
  }



  /// Build an [AudioSource] for a single [Song].
  AudioSource _buildSource(Song s) {
    final tag = MediaItem(
      id: s.fileName,
      title: s.title,
      artist: s.artist,
      album: s.album,
      duration: s.duration,
    );

    if (s.audioBytes != null) {
      return _BytesAudioSource(
        s.audioBytes!,
        tag: tag,
        contentType: _BytesAudioSource.mimeForExtension(s.fileName),
      );
    }

    // filePath may be a filesystem path ("/var/…") from file_picker
    // or a URI string ("content://…", "file://…") from on_audio_query.
    // Uri.file() is needed for bare paths; Uri.parse() for existing URIs.
    final path = s.filePath;
    final Uri uri;
    if (path != null) {
      uri = (path.startsWith('/'))
          ? Uri.file(path)
          : Uri.parse(path);
    } else {
      uri = Uri.file(s.fileName);
    }
    return AudioSource.uri(uri, tag: tag);
  }

  /// Returns true when the given song list matches the already-loaded
  /// audio source, avoiding an expensive rebuild.
  bool _matchesLoadedQueue(List<Song> songs) {
    if (_loadedQueueIds.length != songs.length) return false;
    for (int i = 0; i < songs.length; i++) {
      if (songs[i].fileName != _loadedQueueIds[i]) return false;
    }
    return true;
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
    _currentIndex = newIndex;
    _updateMediaItem();
    notifyListeners();
    // Suppress so currentIndexStream doesn't double-notify for the same index.
    _suppressStreams = true;
    try {
      await _player!.seek(Duration.zero, index: newIndex);
    } finally {
      _suppressStreams = false;
    }
  }

  Future<void> skipNext() async {
    if (_queue.isEmpty || _player == null) return;
    final newIndex = (_currentIndex + 1) % _queue.length;
    _currentIndex = newIndex;
    _updateMediaItem();
    notifyListeners();
    _suppressStreams = true;
    try {
      await _player!.seek(Duration.zero, index: newIndex);
    } finally {
      _suppressStreams = false;
    }
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

  // ── Lock-screen / notification metadata ──

  void _updateMediaItem() {
    final song = currentSong;
    if (song == null || _handler == null) return;

    // Prefer the real duration from the player (resolved after
    // setAudioSource) over the Song model's duration which may
    // still be Duration.zero for freshly imported files.
    final effectiveDuration =
        _duration > Duration.zero ? _duration : song.duration;

    _handler!.mediaItem.add(MediaItem(
      id: song.fileName,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: effectiveDuration,
    ));
  }

  /// Push the full queue to audio_service so lock-screen skip
  /// controls know there are adjacent tracks.
  void _updateQueue() {
    if (_handler == null || _queue.isEmpty) return;
    _handler!.queue.add(
      _queue
          .map((s) => MediaItem(
                id: s.fileName,
                title: s.title,
                artist: s.artist,
                album: s.album,
                duration: s.duration,
              ))
          .toList(),
    );
  }

  // ── Cleanup ──

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _player?.dispose();
    super.dispose();
  }
}

/// A [StreamAudioSource] that serves audio from an in-memory [Uint8List].
/// Used for web imports where only bytes (not file paths) are available.
// ignore: subtype_of_sealed_class
class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  final String _contentType;

  _BytesAudioSource(this._bytes, {super.tag, String? contentType})
      : _contentType = contentType ?? 'audio/mpeg';

  /// Infers a MIME type from a file extension.
  static String mimeForExtension(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      'wav' => 'audio/wav',
      'aac' || 'm4a' => 'audio/mp4',
      'ogg' => 'audio/ogg',
      'aiff' => 'audio/aiff',
      'wma' => 'audio/x-ms-wma',
      _ => 'audio/mpeg',
    };
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final effectiveStart = start ?? 0;
    final effectiveEnd = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: effectiveEnd - effectiveStart,
      offset: effectiveStart,
      // Use buffer view instead of sublist() to avoid copying megabytes
      // of audio data on every range request — prevents GC pauses.
      stream: Stream.value(
        Uint8List.view(
          _bytes.buffer,
          _bytes.offsetInBytes + effectiveStart,
          effectiveEnd - effectiveStart,
        ),
      ),
      contentType: _contentType,
    );
  }
}
