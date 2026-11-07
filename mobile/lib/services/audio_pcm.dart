import 'dart:typed_data';

/// Skips a RIFF/WAV header, if there is one, so the PCM samples start correctly.
Uint8List stripWavHeader(Uint8List bytes) {
  if (bytes.length > 44 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46) {
    // Find the 'data' chunk.
    for (var i = 12; i + 8 < bytes.length; i++) {
      if (bytes[i] == 0x64 &&
          bytes[i + 1] == 0x61 &&
          bytes[i + 2] == 0x74 &&
          bytes[i + 3] == 0x61) {
        final dataStart = i + 8;
        if (dataStart < bytes.length) {
          return Uint8List.sublistView(bytes, dataStart);
        }
      }
    }
    return Uint8List.sublistView(bytes, 44);
  }
  return bytes;
}

/// 16-bit little-endian PCM to samples between -1 and 1.
List<double> pcm16ToFloat(Uint8List bytes) {
  if (bytes.length < 2) return const [];
  final data = ByteData.sublistView(bytes);
  return List<double>.generate(
    bytes.length ~/ 2,
    (i) => data.getInt16(i * 2, Endian.little) / 32768.0,
  );
}
