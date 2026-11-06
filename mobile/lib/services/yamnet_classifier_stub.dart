import 'dart:typed_data';

import 'screening_result.dart';
import 'yamnet_classifier_base.dart';

/// Web and other platforms without TFLite: acoustic screening is unavailable.
class YamnetClassifierStub implements YamnetClassifier {
  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async =>
      unavailableResult(
        reason:
            'Acoustic screening unavailable on this platform — use clinical judgment',
      );

  @override
  Future<void> dispose() async {}
}

Future<YamnetClassifier> createYamnetClassifier() async =>
    YamnetClassifierStub();
