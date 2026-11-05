import 'dart:math' as math;

import 'screening_result.dart';

/// Map 2-class head logits `[normal, abnormal]` to advisory labels.
/// Fail-closed: mid-band → INCONCLUSIVE; never silent GREEN on weak evidence.
ScreeningResult mapOperaCeHeadToResult(List<double> logits) {
  const version = 'opera-ce-head-v0';
  if (logits.isEmpty) {
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason: 'Empty OPERA-CE head output — use MOEWS',
      source: 'opera_ce',
      modelVersion: version,
    );
  }

  final maxL = logits.reduce(math.max);
  var sum = 0.0;
  final exps = List<double>.generate(logits.length, (i) {
    final e = math.exp(logits[i] - maxL);
    sum += e;
    return e;
  });
  final probs = exps.map((e) => e / sum).toList();
  final abnormal = probs.length >= 2 ? probs[1] : probs[0];

  if (abnormal > 0.7) {
    return ScreeningResult(
      label: 'RED',
      confidence: abnormal,
      reason:
          'OPERA-CE abnormal (advisory ${(abnormal * 100).toStringAsFixed(0)}%) — confirm with MOEWS',
      source: 'opera_ce',
      modelVersion: version,
    );
  }
  if (abnormal < 0.5 && probs.length >= 2 && probs[0] > 0.7) {
    return ScreeningResult(
      label: 'GREEN',
      confidence: probs[0],
      reason:
          'OPERA-CE low abnormal score — advisory only, not a clinical clear',
      source: 'opera_ce',
      modelVersion: version,
    );
  }
  return ScreeningResult(
    label: 'INCONCLUSIVE',
    confidence: abnormal,
    reason: 'OPERA-CE uncertain — use MOEWS and clinical judgment',
    source: 'opera_ce',
    modelVersion: version,
  );
}
