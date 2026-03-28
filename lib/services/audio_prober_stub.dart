import 'dart:typed_data';

/// Native stub — duration comes from header parsing; no web Audio probing.
class AudioProber {
  static Future<Duration?> probeDuration({
    Uint8List? bytes,
    required String fileName,
  }) async {
    return null;
  }
}
