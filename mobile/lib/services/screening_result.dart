import 'package:flutter/foundation.dart' show kReleaseMode;

import '../parameters.dart';

/// Demo classifiers (web simulator buttons, `SCREENING_MODEL=stub`) exist only
/// outside release builds. This is a const so release builds tree-shake them.
const bool demoClassifiersEnabled = !kReleaseMode;

class ScreeningResult {
  final String label; // GREEN | RED | INCONCLUSIVE
  final double confidence;
  final String reason;
  final String source; // yamnet | stub | simulator | …
  final String modelVersion;

  ScreeningResult({
    required this.label,
    required this.confidence,
    required this.reason,
    required this.source,
    this.modelVersion = 'unknown-v0',
  });
}

ScreeningResult mapYamnetToResult({required double abnormalScore}) {
  // Higher score = more evidence of respiratory AudioSet events.
  if (abnormalScore > Parameters.acousticRedAbove) {
    return ScreeningResult(
      label: 'RED',
      confidence: abnormalScore,
      reason:
          'Abnormal breathing detected (confidence: ${(abnormalScore * 100).toStringAsFixed(0)}%)',
      source: 'yamnet',
      modelVersion: 'yamnet-audioset-v0',
    );
  }
  // Spec §7.1.1: below 0.5 is inconclusive. A low respiratory-event score only
  // means nothing was detected, so it must never read as a clinical all-clear.
  if (abnormalScore < Parameters.acousticInconclusiveBelow) {
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: abnormalScore,
      reason: 'Inconclusive — use clinical judgment',
      source: 'yamnet',
      modelVersion: 'yamnet-audioset-v0',
    );
  }
  // Mid-band is uncertain — never label as "normal breathing".
  return ScreeningResult(
    label: 'INCONCLUSIVE',
    confidence: abnormalScore,
    reason: 'Uncertain mid-band score — use MOEWS and clinical judgment',
    source: 'yamnet',
    modelVersion: 'yamnet-audioset-v0',
  );
}

/// Every load, inference and microphone failure ends here: never GREEN or RED.
ScreeningResult unavailableResult({
  String reason = 'Screening unavailable — use clinical judgment',
}) =>
    ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason: reason,
      source: 'unavailable',
      modelVersion: 'unavailable-v0',
    );

/// Acoustic screening switched off (`MOEWS_ONLY`): vitals decide alone.
ScreeningResult moewsOnlyResult() => ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason:
          'Acoustic screening disabled (MOEWS_ONLY) — use vitals and judgment',
      source: 'moews_only',
      modelVersion: 'moews-only-v0',
    );

/// `SCREENING_MODEL=stub`: labelled demo output, and still never reassuring.
ScreeningResult stubClassify() => ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason: 'Stub classifier (demo) — use clinical judgment',
      source: 'stub',
      modelVersion: 'stub-v0',
    );

/// Web demo buttons. Outside debug/profile builds this is [unavailableResult].
ScreeningResult simulatorClassify({required bool forceRed}) {
  if (!demoClassifiersEnabled) return unavailableResult();
  return _demoSimulatorResult(forceRed: forceRed);
}

ScreeningResult _demoSimulatorResult({required bool forceRed}) =>
    ScreeningResult(
      label: forceRed ? 'RED' : 'GREEN',
      confidence: forceRed ? 0.82 : 0.91,
      reason: forceRed
          ? 'Simulator: abnormal breathing (demo)'
          : 'Simulator: normal breathing (demo)',
      source: 'simulator',
      modelVersion: 'simulator-v0',
    );
