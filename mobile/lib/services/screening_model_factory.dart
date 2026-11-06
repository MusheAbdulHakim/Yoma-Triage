import 'dart:typed_data';

import '../config.dart';
import 'opera_ce_classifier.dart';
import 'screening_result.dart';
import 'yamnet_classifier.dart';

/// Placeholder classifiers for models not yet bundled (ToS / TFLite spike pending).
class PackPendingClassifier implements YamnetClassifier {
  PackPendingClassifier(this.modelId);

  final String modelId;

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason:
          '$modelId model pack not installed — use MOEWS and clinical judgment',
      source: modelId,
      modelVersion: '$modelId-pending',
    );
  }

  @override
  Future<void> dispose() async {}
}

class _StubClassifier implements YamnetClassifier {
  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    return demoClassifiersEnabled ? stubClassify() : unavailableResult();
  }

  @override
  Future<void> dispose() async {}
}

class _MoewsOnlyClassifier implements YamnetClassifier {
  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    return moewsOnlyResult();
  }

  @override
  Future<void> dispose() async {}
}

/// Factory: respects [ScreeningConfig.moewsOnly] and [ScreeningConfig.model].
Future<YamnetClassifier> createConfiguredClassifier() async {
  if (ScreeningConfig.moewsOnly) {
    return _MoewsOnlyClassifier();
  }
  switch (ScreeningConfig.model) {
    case 'stub':
      return _StubClassifier();
    case 'hear_event':
      return PackPendingClassifier('hear_event');
    case 'opera_ce':
      return createOperaCeClassifier();
    case 'yamnet':
    default:
      return createYamnetClassifier();
  }
}
