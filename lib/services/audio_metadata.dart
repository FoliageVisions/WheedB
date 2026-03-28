import 'dart:typed_data';

/// Parsed audio file metadata.
class AudioMetadata {
  final int sampleRateHz;
  final int bitDepth;
  final Duration? duration;

  const AudioMetadata({
    required this.sampleRateHz,
    required this.bitDepth,
    this.duration,
  });
}

/// Extracts sample rate, bit depth, and duration from audio file headers.
class AudioMetadataParser {
  /// Parse metadata from audio file bytes.
  ///
  /// [bytes] — raw audio bytes (at least the first 8 KB for header-only
  /// parsing; full file gives better results for M4A/MP3).
  /// [fileName] — used to determine the format by extension.
  /// [fileSize] — total file size in bytes (used for MP3 CBR duration
  /// estimation when only a header is available).
  static AudioMetadata parse(
    Uint8List bytes,
    String fileName, {
    int? fileSize,
  }) {
    final ext = fileName.split('.').last.toLowerCase();
    try {
      return switch (ext) {
        'wav' => _parseWav(bytes),
        'flac' => _parseFlac(bytes),
        'aiff' || 'aif' => _parseAiff(bytes),
        'mp3' => _parseMp3(bytes, fileSize: fileSize ?? bytes.length),
        'm4a' || 'aac' || 'mp4' => _parseM4a(bytes),
        _ => const AudioMetadata(sampleRateHz: 44100, bitDepth: 16),
      };
    } catch (_) {
      return const AudioMetadata(sampleRateHz: 44100, bitDepth: 16);
    }
  }

  // ── WAV ───────────────────────────────────────────────────────────

  static AudioMetadata _parseWav(Uint8List b) {
    if (b.length < 44) {
      return const AudioMetadata(sampleRateHz: 44100, bitDepth: 16);
    }

    // Locate "fmt " sub-chunk.
    final fmt = _findRiffChunk(b, 12, 0x666D7420); // "fmt "
    if (fmt == null || fmt.dataOffset + 16 > b.length) {
      return const AudioMetadata(sampleRateHz: 44100, bitDepth: 16);
    }

    final o = fmt.dataOffset;
    final numCh = _u16le(b, o + 2);
    final sr = _u32le(b, o + 4);
    final bd = _u16le(b, o + 14);

    // Locate "data" sub-chunk for duration.
    Duration? dur;
    final data = _findRiffChunk(b, 12, 0x64617461); // "data"
    if (data != null && sr > 0 && numCh > 0 && bd > 0) {
      final bytesPerSample = bd ~/ 8;
      final totalSamples = data.chunkSize ~/ (numCh * bytesPerSample);
      dur = Duration(milliseconds: (totalSamples * 1000 ~/ sr));
    }

    return AudioMetadata(sampleRateHz: sr, bitDepth: bd, duration: dur);
  }

  // ── FLAC ──────────────────────────────────────────────────────────

  static AudioMetadata _parseFlac(Uint8List b) {
    if (b.length < 42) {
      return const AudioMetadata(sampleRateHz: 44100, bitDepth: 16);
    }

    // Check "fLaC" magic.
    if (b[0] != 0x66 || b[1] != 0x4C || b[2] != 0x61 || b[3] != 0x43) {
      return const AudioMetadata(sampleRateHz: 44100, bitDepth: 16);
    }

    // STREAMINFO block starts at byte 8 (after block header at byte 4).
    // Layout (at byte offsets from 8):
    //  0-1   min block size
    //  2-3   max block size
    //  4-6   min frame size
    //  7-9   max frame size
    // 10-12  sample rate (20 bits) + channels−1 (3 bits) + bps−1 (5 bits)
    // 13-17  total samples (36 bits, lower 4 of byte 13 + bytes 14-17)
    final sampleRate =
        (b[18] << 12) | (b[19] << 4) | (b[20] >> 4);
    final bitDepth = ((b[20] & 0x01) << 4 | (b[21] >> 4)) + 1;

    // Total samples: 4 bits from byte 21 + bytes 22-25.
    final totalSamples = ((b[21] & 0x0F) * 4294967296) + // << 32
        ((b[22] << 24) |
        (b[23] << 16) |
        (b[24] << 8) |
        b[25]);

    Duration? dur;
    if (sampleRate > 0 && totalSamples > 0) {
      dur = Duration(milliseconds: (totalSamples * 1000 ~/ sampleRate));
    }

    return AudioMetadata(
      sampleRateHz: sampleRate,
      bitDepth: bitDepth,
      duration: dur,
    );
  }

  // ── AIFF ──────────────────────────────────────────────────────────

  static AudioMetadata _parseAiff(Uint8List b) {
    if (b.length < 30) {
      return const AudioMetadata(sampleRateHz: 44100, bitDepth: 16);
    }

    // Locate COMM chunk (big-endian sizes).
    final comm = _findAiffChunk(b, 12, 0x434F4D4D); // "COMM"
    if (comm == null || comm.dataOffset + 18 > b.length) {
      return const AudioMetadata(sampleRateHz: 44100, bitDepth: 16);
    }

    final o = comm.dataOffset;
    final numSampleFrames = _u32be(b, o + 2);
    final bd = _u16be(b, o + 6);
    final sr = _parseIeee80(b, o + 8);

    Duration? dur;
    if (sr > 0 && numSampleFrames > 0) {
      dur = Duration(milliseconds: (numSampleFrames * 1000 ~/ sr));
    }

    return AudioMetadata(sampleRateHz: sr, bitDepth: bd, duration: dur);
  }

  // ── MP3 ───────────────────────────────────────────────────────────

  static AudioMetadata _parseMp3(Uint8List b, {required int fileSize}) {
    int offset = 0;

    // Skip ID3v2 tag if present.
    if (b.length > 10 &&
        b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
      final tagSize = ((b[6] & 0x7F) << 21) |
          ((b[7] & 0x7F) << 14) |
          ((b[8] & 0x7F) << 7) |
          (b[9] & 0x7F);
      offset = 10 + tagSize;
    }

    int sampleRate = 44100;
    int bitrateKbps = 128;

    // MPEG1 Layer III bitrate table (kbps).
    const brV1L3 = [
      0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, -1
    ];
    // MPEG2 / 2.5 Layer III.
    const brV2L3 = [
      0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, -1
    ];
    // Sample rate tables.
    const srTable = [
      [44100, 48000, 32000], // MPEG1
      [22050, 24000, 16000], // MPEG2
      [11025, 12000, 8000], // MPEG2.5
    ];

    for (int i = offset; i < b.length - 4; i++) {
      if (b[i] != 0xFF || (b[i + 1] & 0xE0) != 0xE0) continue;

      final version = (b[i + 1] >> 3) & 0x03;
      final layer = (b[i + 1] >> 1) & 0x03;
      final brIdx = (b[i + 2] >> 4) & 0x0F;
      final srIdx = (b[i + 2] >> 2) & 0x03;

      // Reject reserved values.
      if (version == 1 || layer == 0 || brIdx == 0 || brIdx == 15 || srIdx == 3) {
        continue;
      }

      final vIdx = version == 3 ? 0 : (version == 2 ? 1 : 2);
      sampleRate = srTable[vIdx][srIdx];
      bitrateKbps = version == 3 ? brV1L3[brIdx] : brV2L3[brIdx];
      break;
    }

    Duration? dur;
    if (bitrateKbps > 0 && fileSize > 0) {
      final durationMs = (fileSize * 8) ~/ bitrateKbps; // ms = bytes*8 / kbps
      dur = Duration(milliseconds: durationMs);
    }

    return AudioMetadata(sampleRateHz: sampleRate, bitDepth: 16, duration: dur);
  }

  // ── M4A / AAC (MPEG-4 container) ─────────────────────────────────

  static AudioMetadata _parseM4a(Uint8List b) {
    // Traverse top-level atoms to find "moov".
    int offset = 0;
    int? moovStart;
    int? moovEnd;

    while (offset + 8 <= b.length) {
      final size = _u32be(b, offset);
      if (size < 8) break;

      if (b[offset + 4] == 0x6D &&
          b[offset + 5] == 0x6F &&
          b[offset + 6] == 0x6F &&
          b[offset + 7] == 0x76) {
        moovStart = offset + 8;
        moovEnd = offset + size;
        break;
      }
      offset += size;
    }

    if (moovStart == null || moovEnd == null || moovEnd > b.length) {
      return const AudioMetadata(sampleRateHz: 44100, bitDepth: 16);
    }

    // Find "mvhd" inside moov.
    offset = moovStart;
    while (offset + 8 <= moovEnd) {
      final size = _u32be(b, offset);
      if (size < 8) break;

      if (b[offset + 4] == 0x6D &&
          b[offset + 5] == 0x76 &&
          b[offset + 6] == 0x68 &&
          b[offset + 7] == 0x64) {
        final d = offset + 8;
        if (d + 20 > b.length) break;
        final version = b[d];

        int timeScale;
        int durationVal;
        if (version == 0 && d + 20 <= b.length) {
          timeScale = _u32be(b, d + 12);
          durationVal = _u32be(b, d + 16);
        } else if (d + 28 <= b.length) {
          timeScale = _u32be(b, d + 20);
          durationVal = _u32be(b, d + 24);
        } else {
          break;
        }

        Duration? dur;
        if (timeScale > 0) {
          dur = Duration(milliseconds: durationVal * 1000 ~/ timeScale);
        }

        // AAC is inherently ~16-bit lossy; sample rate defaults to 44100.
        return AudioMetadata(sampleRateHz: 44100, bitDepth: 16, duration: dur);
      }

      offset += size;
    }

    return const AudioMetadata(sampleRateHz: 44100, bitDepth: 16);
  }

  // ── Chunk search helpers ──────────────────────────────────────────

  static ({int dataOffset, int chunkSize})? _findRiffChunk(
      Uint8List b, int start, int id) {
    for (int i = start; i + 8 <= b.length; i++) {
      if ((b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3]) == id) {
        return (dataOffset: i + 8, chunkSize: _u32le(b, i + 4));
      }
    }
    return null;
  }

  static ({int dataOffset, int chunkSize})? _findAiffChunk(
      Uint8List b, int start, int id) {
    for (int i = start; i + 8 <= b.length; i++) {
      if ((b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3]) == id) {
        return (dataOffset: i + 8, chunkSize: _u32be(b, i + 4));
      }
    }
    return null;
  }

  // ── Byte reading helpers ──────────────────────────────────────────

  static int _u16le(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

  static int _u32le(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static int _u16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

  static int _u32be(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// Parse IEEE 754 80-bit extended precision float (big-endian).
  /// Used by AIFF for sample rate.
  static int _parseIeee80(Uint8List b, int o) {
    final exponent = ((b[o] & 0x7F) << 8) | b[o + 1];
    final mantissa = _u32be(b, o + 2);
    if (exponent == 0 && mantissa == 0) return 0;
    final e = exponent - 16383;
    if (e >= 0 && e <= 31) return mantissa >> (31 - e);
    return 0;
  }
}
