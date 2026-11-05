import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'screening_result.dart';
import 'yamnet_classifier_base.dart';

/// Web / platforms without TFLite: never invent GREEN/RED for OPERA-CE.
class OperaCeClassifierStub implements YamnetClassifier {
  OperaCeClassifierStub({this.encoderPresent = false});

  final bool encoderPresent;

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    if (encoderPresent) {
      return ScreeningResult(
        label: 'INCONCLUSIVE',
        confidence: 0.0,
        reason:
            'OPERA-CE encoder present; TFLite unavailable on this platform — use MOEWS',
        source: 'opera_ce',
        modelVersion: 'opera-ce-encoder-v0',
      );
    }
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason:
          'opera_ce encoder pack not installed — use MOEWS and clinical judgment',
      source: 'opera_ce',
      modelVersion: 'opera_ce-pending',
    );
  }

  @override
  Future<void> dispose() async {}
}

Future<YamnetClassifier> createOperaCeClassifier() async {
  var present = false;
  try {
    await rootBundle.load('assets/models/opera_ce_encoder.tflite');
    present = true;
  } catch (_) {
    present = false;
  }
  return OperaCeClassifierStub(encoderPresent: present);
}
