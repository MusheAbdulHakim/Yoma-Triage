import 'dart:typed_data';

/// Platform audio capture contract (16 kHz mono PCM).
abstract class AudioRecorderService {
  Future<void> start();
  Future<Uint8List> stop();
  Future<void> dispose();
}
