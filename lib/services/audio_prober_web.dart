import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Probes audio duration on the web by creating a temporary <audio> element
/// backed by a Blob URL.
class AudioProber {
  static Future<Duration?> probeDuration({
    Uint8List? bytes,
    required String fileName,
  }) async {
    if (bytes == null || bytes.isEmpty) return null;

    try {
      final jsBytes = bytes.toJS;
      final blob = web.Blob(<JSAny>[jsBytes].toJS);
      final url = web.URL.createObjectURL(blob);

      try {
        final audio = web.HTMLAudioElement();
        final completer = Completer<Duration?>();

        audio.addEventListener(
          'loadedmetadata',
          ((web.Event _) {
            final secs = audio.duration;
            if (!secs.isNaN && secs.isFinite && secs > 0) {
              completer.complete(
                Duration(milliseconds: (secs * 1000).round()),
              );
            } else {
              if (!completer.isCompleted) completer.complete(null);
            }
          }).toJS,
        );

        audio.addEventListener(
          'error',
          ((web.Event _) {
            if (!completer.isCompleted) completer.complete(null);
          }).toJS,
        );

        audio.src = url;
        audio.load();

        return await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
      } finally {
        web.URL.revokeObjectURL(url);
      }
    } catch (_) {
      return null;
    }
  }
}
