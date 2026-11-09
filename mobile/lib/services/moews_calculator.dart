import '../parameters.dart';

class MoewsResult {
  const MoewsResult({
    required this.score,
    required this.riskLevel,
    this.hrScore = 0,
    this.sbpScore = 0,
    this.dbpScore = 0,
    this.rrScore = 0,
    this.tempScore = 0,
    this.spo2Score = 0,
    this.consciousnessScore = 0,
    this.missingVitals = const [],
  });

  final int? score;
  final String riskLevel;

  /// Per-vital MOEWS contribution (0 / 1 / 3). Used for CHO UI highlighting.
  final int hrScore;
  final int sbpScore;
  final int dbpScore;
  final int rrScore;
  final int tempScore;
  final int spo2Score;
  final int consciousnessScore;

  /// API names of the vitals that were not measured.
  final List<String> missingVitals;

  bool get hrAbnormal => hrScore > 0;

  bool get isIncomplete => riskLevel == 'INCOMPLETE';

  /// What the CHO sees about missing vitals, or null if nothing is missing.
  String? get notMeasuredText {
    if (missingVitals.isEmpty) return null;
    if (missingVitals.length == 1 && missingVitals.first == 'spo2') {
      return 'SpO₂ not measured';
    }
    final labels = missingVitals.map((name) => _vitalLabels[name] ?? name);
    return 'Not measured: ${labels.join(', ')}';
  }
}

const _vitalLabels = {
  'systolic_bp': 'Systolic BP',
  'diastolic_bp': 'Diastolic BP',
  'heart_rate': 'Heart rate',
  'respiratory_rate': 'Respiratory rate',
  'temperature': 'Temperature',
  'spo2': 'SpO₂',
  'consciousness_level': 'AVPU',
};

int _scoreBand(MoewsBand band, num value) {
  final below = band.redBelow;
  final above = band.redAbove;
  if ((below != null && value < below) || (above != null && value > above)) {
    return 3;
  }
  final lowMin = band.yellowLowMin;
  final lowMax = band.yellowLowMax;
  if (lowMin != null && lowMax != null && value >= lowMin && value <= lowMax) {
    return 1;
  }
  final highMin = band.yellowHighMin;
  final highMax = band.yellowHighMax;
  if (highMin != null && highMax != null && value >= highMin && value <= highMax) {
    return 1;
  }
  return 0;
}

int _scoreConsciousness(String consciousness) {
  if (consciousness.toUpperCase() != 'A') return 3;
  return 0;
}

String _riskLevel(List<int> scores, int total, List<String> missing) {
  // A measured critical value is never hidden by what wasn't measured.
  if (scores.any((s) => s == Parameters.moewsRedParameterScore) ||
      total >= Parameters.moewsRedTotal) {
    return 'RED';
  }
  // A patient can't be called normal from half a set. SpO₂ alone is optional.
  if (missing.any((name) => name != 'spo2')) return 'INCOMPLETE';
  if (total >= Parameters.moewsYellowTotal || scores.any((s) => s == 1)) {
    return 'YELLOW';
  }
  return 'GREEN';
}

/// Scores what was measured. Keep in step with `src/tools/moews_calculator.py`;
/// `tests/fixtures/moews_cases.json` runs against both.
MoewsResult calculateMoews({
  required int? sbp,
  required int? dbp,
  required int? hr,
  required int? rr,
  required double? temp,
  int? spo2,
  String? consciousness = 'A',
}) {
  final sbpScore = sbp == null ? 0 : _scoreBand(Parameters.systolicBpBand, sbp);
  final dbpScore = dbp == null ? 0 : _scoreBand(Parameters.diastolicBpBand, dbp);
  final hrScore = hr == null ? 0 : _scoreBand(Parameters.heartRateBand, hr);
  final rrScore = rr == null ? 0 : _scoreBand(Parameters.respiratoryRateBand, rr);
  final tempScore = temp == null ? 0 : _scoreBand(Parameters.temperatureBand, temp);
  final spo2Score = spo2 == null ? 0 : _scoreBand(Parameters.spo2Band, spo2);
  final consciousnessScore = consciousness == null ? 0 : _scoreConsciousness(consciousness);

  final scores = <int>[
    if (sbp != null) sbpScore,
    if (dbp != null) dbpScore,
    if (hr != null) hrScore,
    if (rr != null) rrScore,
    if (temp != null) tempScore,
    if (spo2 != null) spo2Score,
    if (consciousness != null) consciousnessScore,
  ];
  final missing = <String>[
    if (sbp == null) 'systolic_bp',
    if (dbp == null) 'diastolic_bp',
    if (hr == null) 'heart_rate',
    if (rr == null) 'respiratory_rate',
    if (temp == null) 'temperature',
    if (spo2 == null) 'spo2',
    if (consciousness == null) 'consciousness_level',
  ];

  final total = scores.fold<int>(0, (sum, s) => sum + s);
  return MoewsResult(
    score: scores.isEmpty ? null : total,
    riskLevel: _riskLevel(scores, total, missing),
    hrScore: hrScore,
    sbpScore: sbpScore,
    dbpScore: dbpScore,
    rrScore: rrScore,
    tempScore: tempScore,
    spo2Score: spo2Score,
    consciousnessScore: consciousnessScore,
    missingVitals: missing,
  );
}
