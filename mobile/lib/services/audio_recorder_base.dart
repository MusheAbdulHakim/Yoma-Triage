import 'dart:typed_data';

/// Platform audio capture contract (16 kHz mono PCM).
abstract class AudioRecorderService {
  Future<void> start();
  Future<Uint8List> stop();
  Future<void> dispose();

  /// The live microphone level while recording, 0 (silent) to 1 (loud), a few times a
  /// second. For the screen only: it never touches the recording or the classifier.
  Stream<double> levels();
}

/// Maps a dBFS reading to 0–1 for the pulse. Below -55 dBFS reads as silence; breathing
/// close to the phone (about -40 to -25 dBFS) fills most of the range, and -20 dBFS or louder
/// is full. Display only: the recording and the classifier never see this number.
double levelFromDbfs(double dbfs) {
  if (dbfs.isNaN) return 0;
  return ((dbfs + 55) / 35).clamp(0.0, 1.0);
}
