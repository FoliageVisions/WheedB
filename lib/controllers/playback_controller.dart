import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';

/// Lightweight playback state manager.
///
/// Simulates playback with a periodic timer so the UI can be developed and
/// tested without a real audio engine. Replace the timer with actual audio
/// player callbacks when integrating a plugin like just_audio.
class PlaybackController extends ChangeNotifier {
  List<Song> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Timer? _ticker;

  // ── Back-button double-press detection ──
  DateTime? _lastBackPress;
  static const _doublePressWindow = Duration(milliseconds: 1500);

  // ── Public getters ──
  Song? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => currentSong?.duration ?? Duration.zero;
  Duration get remaining => duration - _position;
  bool get hasQueue => _queue.isNotEmpty;

  // ── Queue management ──
  void loadQueue(List<Song> songs, {int startIndex = 0}) {
    _queue = List.of(songs);
    _currentIndex = startIndex.clamp(0, _queue.length - 1);
    _position = Duration.zero;
    _isPlaying = false;
    _stopTicker();
    notifyListeners();
  }

  // ── Transport controls ──
  void togglePlayPause() {
    if (currentSong == null) return;
    _isPlaying = !_isPlaying;
    _isPlaying ? _startTicker() : _stopTicker();
    notifyListeners();
  }

  void seekTo(Duration target) {
    if (target < Duration.zero) {
      _position = Duration.zero;
    } else if (target > duration) {
      _position = duration;
    } else {
      _position = target;
    }
    notifyListeners();
  }

  /// Single press → reset to 0:00.
  /// Double press within 1.5 s → skip to previous track.
  void handleBack() {
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) <= _doublePressWindow) {
      _lastBackPress = null;
      skipPrevious();
    } else {
      _lastBackPress = now;
      seekTo(Duration.zero);
    }
  }

  void skipPrevious() {
    if (_queue.isEmpty) return;
    _currentIndex =
        (_currentIndex - 1 < 0) ? _queue.length - 1 : _currentIndex - 1;
    _position = Duration.zero;
    notifyListeners();
  }

  void skipNext() {
    if (_queue.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _queue.length;
    _position = Duration.zero;
    notifyListeners();
  }

  // ── Simulated tick (1 s resolution) ──
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_position < duration) {
        _position += const Duration(seconds: 1);
        notifyListeners();
      } else {
        skipNext();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
