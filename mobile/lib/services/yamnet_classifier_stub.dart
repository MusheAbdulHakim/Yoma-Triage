import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'screening_result.dart';
import 'yamnet_classifier_base.dart';

/// Web / fallback: never loads TFLite. Uses stub classifier.
class YamnetClassifierStub implements YamnetClassifier {
  YamnetClassifierStub({this.forceRed = false, this.modelPresent = false});

  final bool forceRed;
  final bool modelPresent;

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    final result = stubClassify(forceRed: forceRed);
    if (modelPresent) {
      return ScreeningResult(
        label: result.label,
        confidence: result.confidence,
        reason:
            '${result.reason} (model asset present; TFLite unavailable on this platform)',
        source: 'stub',
      );
    }
    return result;
  }

  @override
  Future<void> dispose() async {}
}

Future<YamnetClassifier> createYamnetClassifier({bool forceRed = false}) async {
  var modelPresent = false;
  try {
    await rootBundle.load('assets/models/yamnet.tflite');
    modelPresent = true;
  } catch (_) {
    modelPresent = false;
  }
  return YamnetClassifierStub(forceRed: forceRed, modelPresent: modelPresent);
}
