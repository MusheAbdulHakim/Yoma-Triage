import 'dart:typed_data';

import 'screening_result.dart';

/// Platform-agnostic YAMNet classifier contract.
abstract class YamnetClassifier {
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes);

  Future<void> dispose();
}
