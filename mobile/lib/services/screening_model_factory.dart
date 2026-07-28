import 'dart:typed_data';

import '../config.dart';
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

class _ForceStubClassifier implements YamnetClassifier {
  _ForceStubClassifier({required this.forceRed});

  final bool forceRed;

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    return stubClassify(forceRed: forceRed);
  }

  @override
  Future<void> dispose() async {}
}

class _MoewsOnlyClassifier implements YamnetClassifier {
  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason:
          'Acoustic screening disabled (MOEWS_ONLY) — use vitals and judgment',
      source: 'moews_only',
      modelVersion: 'moews-only-v0',
    );
  }

  @override
  Future<void> dispose() async {}
}

/// Factory: respects [ScreeningConfig.moewsOnly] and [ScreeningConfig.model].
Future<YamnetClassifier> createConfiguredClassifier({
  bool forceRed = false,
}) async {
  if (ScreeningConfig.moewsOnly) {
    return _MoewsOnlyClassifier();
  }
  switch (ScreeningConfig.model) {
    case 'stub':
      return _ForceStubClassifier(forceRed: forceRed);
    case 'hear_event':
      return PackPendingClassifier('hear_event');
    case 'opera_ce':
      return PackPendingClassifier('opera_ce');
    case 'yamnet':
    default:
      return createYamnetClassifier(forceRed: forceRed);
  }
}
