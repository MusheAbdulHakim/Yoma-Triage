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

int _scoreSbp(int sbp) {
  if (sbp < 80 || sbp > 150) return 3;
  if ((sbp >= 80 && sbp <= 90) || (sbp >= 140 && sbp <= 150)) return 1;
  return 0;
}

int _scoreDbp(int dbp) {
  if (dbp > 100) return 3;
  if (dbp >= 90 && dbp <= 100) return 1;
  if (dbp < 60) return 3;
  return 0;
}

int _scoreHr(int hr) {
  if (hr < 50 || hr > 130) return 3;
  if ((hr >= 50 && hr <= 60) || (hr >= 110 && hr <= 130)) return 1;
  return 0;
}

int _scoreRr(int rr) {
  if (rr < 10 || rr > 30) return 3;
  if ((rr >= 10 && rr <= 14) || (rr >= 24 && rr <= 30)) return 1;
  return 0;
}

int _scoreTemp(double temp) {
  if (temp < 35 || temp > 39) return 3;
  if ((temp >= 35 && temp <= 36) || (temp >= 38 && temp <= 39)) return 1;
  return 0;
}

int _scoreSpo2(int spo2) {
  if (spo2 < 90) return 3;
  if (spo2 >= 90 && spo2 <= 94) return 1;
  return 0;
}

int _scoreConsciousness(String consciousness) {
  if (consciousness.toUpperCase() != 'A') return 3;
  return 0;
}

String _riskLevel(List<int> scores, int total) {
  if (scores.any((s) => s == 3) || total >= 5) return 'RED';
  if (total >= 3 || scores.any((s) => s == 1)) return 'YELLOW';
  return 'GREEN';
}

MoewsResult calculateMoews({
  required int? sbp,
  required int? dbp,
  required int? hr,
  required int? rr,
  required double? temp,
  int? spo2,
  String consciousness = 'A',
}) {
  final required = [sbp, dbp, hr, rr, temp];
  if (required.any((v) => v == null)) {
    return const MoewsResult(score: null, riskLevel: 'UNKNOWN');
  }

  final sbpScore = _scoreSbp(sbp!);
  final dbpScore = _scoreDbp(dbp!);
  final hrScore = _scoreHr(hr!);
  final rrScore = _scoreRr(rr!);
  final tempScore = _scoreTemp(temp!);
  final consciousnessScore = _scoreConsciousness(consciousness);
  final spo2Score = spo2 == null ? 0 : _scoreSpo2(spo2);

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
