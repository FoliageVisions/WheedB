import 'package:flutter/foundation.dart';

/// Holds all user-configurable audio/playback settings.
class AudioSettings extends ChangeNotifier {
  bool _gaplessPlayback = false;
  bool _waveformVisualization = false;
  bool _equalizerEnabled = false;
  bool _crossfadeEnabled = false;
  int _crossfadeDurationSeconds = 3;

  /// 10-band EQ gains in dB, range –12 to +12.
  /// Bands: 31 Hz, 62 Hz, 125 Hz, 250 Hz, 500 Hz, 1 kHz, 2 kHz, 4 kHz, 8 kHz, 16 kHz.
  final List<double> _eqBands = List.filled(10, 0.0);

  static const List<String> bandLabels = [
    '31',
    '62',
    '125',
    '250',
    '500',
    '1k',
    '2k',
    '4k',
    '8k',
    '16k',
  ];

  static const List<int> crossfadeOptions = [1, 3, 5, 8];

  // ── Getters ──
  bool get gaplessPlayback => _gaplessPlayback;
  bool get waveformVisualization => _waveformVisualization;
  bool get equalizerEnabled => _equalizerEnabled;
  bool get crossfadeEnabled => _crossfadeEnabled;
  int get crossfadeDurationSeconds => _crossfadeDurationSeconds;
  List<double> get eqBands => List.unmodifiable(_eqBands);

  // ── Setters ──
  set gaplessPlayback(bool v) {
    _gaplessPlayback = v;
    notifyListeners();
  }

  set waveformVisualization(bool v) {
    _waveformVisualization = v;
    notifyListeners();
  }

  set equalizerEnabled(bool v) {
    _equalizerEnabled = v;
    notifyListeners();
  }

  set crossfadeEnabled(bool v) {
    _crossfadeEnabled = v;
    notifyListeners();
  }

  set crossfadeDurationSeconds(int v) {
    _crossfadeDurationSeconds = v;
    notifyListeners();
  }

  void setEqBand(int index, double dB) {
    _eqBands[index] = dB.clamp(-12.0, 12.0);
    notifyListeners();
  }

  void resetEqualizer() {
    for (var i = 0; i < _eqBands.length; i++) {
      _eqBands[i] = 0.0;
    }
    notifyListeners();
  }
}
