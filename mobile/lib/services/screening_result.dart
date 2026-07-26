class ScreeningResult {
  final String label; // GREEN | RED | INCONCLUSIVE
  final double confidence;
  final String reason;
  final String source; // yamnet | stub | simulator

  ScreeningResult({
    required this.label,
    required this.confidence,
    required this.reason,
    required this.source,
  });
}

ScreeningResult mapYamnetToResult({required double abnormalScore}) {
  if (abnormalScore > 0.7) {
    return ScreeningResult(
      label: 'RED',
      confidence: abnormalScore,
      reason:
          'Abnormal breathing detected (confidence: ${(abnormalScore * 100).toStringAsFixed(0)}%)',
      source: 'yamnet',
    );
  } else if (abnormalScore < 0.5) {
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: abnormalScore,
      reason: 'Low confidence — use clinical judgment',
      source: 'yamnet',
    );
  }
  return ScreeningResult(
    label: 'GREEN',
    confidence: abnormalScore,
    reason: 'Normal breathing pattern',
    source: 'yamnet',
  );
}

ScreeningResult stubClassify({required bool forceRed}) => ScreeningResult(
      label: forceRed ? 'RED' : 'GREEN',
      confidence: forceRed ? 0.85 : 0.9,
      reason: forceRed ? 'Stub: Code Red (demo)' : 'Stub: Normal (demo)',
      source: 'stub',
    );

ScreeningResult simulatorClassify({required bool forceRed}) => ScreeningResult(
      label: forceRed ? 'RED' : 'GREEN',
      confidence: forceRed ? 0.82 : 0.91,
      reason: forceRed
          ? 'Simulator: abnormal breathing (demo)'
          : 'Simulator: normal breathing (demo)',
      source: 'simulator',
    );
