import '../generated/clinical_parameters.dart';

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

  bool get hrAbnormal => hrScore > 0;
}

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
  if (highMin != null &&
      highMax != null &&
      value >= highMin &&
      value <= highMax) {
    return 1;
  }
  return 0;
}

int _scoreConsciousness(String consciousness) {
  if (consciousness.toUpperCase() != 'A') return 3;
  return 0;
}

String _riskLevel(List<int> scores, int total) {
  if (scores.any((s) => s == ClinicalParameters.moewsRiskRedParameterScore) ||
      total >= ClinicalParameters.moewsRiskRedTotal) {
    return 'RED';
  }
  if (total >= ClinicalParameters.moewsRiskYellowTotal ||
      scores.any((s) => s == 1)) {
    return 'YELLOW';
  }
  return 'GREEN';
}

MoewsResult calculateMoews({
  required int? sbp,
  required int? dbp,
  required int? hr,
  required int? rr,
  required double? temp,
  int? spo2,
  String? consciousness = 'A',
}) {
  // Consciousness scores 3 when impaired, so unmeasured must not read as Alert.
  final required = [sbp, dbp, hr, rr, temp, consciousness];
  if (required.any((v) => v == null)) {
    return const MoewsResult(score: null, riskLevel: 'UNKNOWN');
  }

  final sbpScore = _scoreBand(ClinicalParameters.systolicBpBand, sbp!);
  final dbpScore = _scoreBand(ClinicalParameters.diastolicBpBand, dbp!);
  final hrScore = _scoreBand(ClinicalParameters.heartRateBand, hr!);
  final rrScore = _scoreBand(ClinicalParameters.respiratoryRateBand, rr!);
  final tempScore = _scoreBand(ClinicalParameters.temperatureBand, temp!);
  final consciousnessScore = _scoreConsciousness(consciousness!);
  final spo2Score = spo2 == null ? 0 : _scoreBand(ClinicalParameters.spo2Band, spo2);

  final scores = <int>[
    sbpScore,
    dbpScore,
    hrScore,
    rrScore,
    tempScore,
    consciousnessScore,
    if (spo2 != null) spo2Score,
  ];

  final total = scores.fold<int>(0, (sum, s) => sum + s);
  return MoewsResult(
    score: total,
    riskLevel: _riskLevel(scores, total),
    hrScore: hrScore,
    sbpScore: sbpScore,
    dbpScore: dbpScore,
    rrScore: rrScore,
    tempScore: tempScore,
    spo2Score: spo2Score,
    consciousnessScore: consciousnessScore,
  );
}
