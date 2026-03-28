import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// AudioHandler that bridges just_audio with audio_service for background
/// playback and lock-screen / notification controls.
class WheedBAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<Duration>? _positionSub;

  WheedBAudioHandler(this._player) {
    // Forward player state to audio_service's playbackState stream.
    _eventSub = _player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });

    // Also push position updates so the lock-screen progress bar
    // stays in sync even between playback events.
    _positionSub = _player.positionStream.listen((_) {
      if (_player.playing) {
        playbackState.add(_transformEvent(_player.playbackEvent));
      }
    });
  }

  // ── Transport controls (called from notification / lock-screen) ──

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      _eventSub?.cancel();
      _positionSub?.cancel();
      await _player.dispose();
    }
    await super.customAction(name, extras);
  }

  /// Map just_audio's PlaybackEvent into audio_service's PlaybackState.
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
    );
  }
}
