class MoewsResult {
  const MoewsResult({required this.score, required this.riskLevel});

  final int? score;
  final String riskLevel;
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

  final scores = <int>[
    _scoreSbp(sbp!),
    _scoreDbp(dbp!),
    _scoreHr(hr!),
    _scoreRr(rr!),
    _scoreTemp(temp!),
    _scoreConsciousness(consciousness),
  ];
  if (spo2 != null) {
    scores.add(_scoreSpo2(spo2));
  }

  final total = scores.fold<int>(0, (sum, s) => sum + s);
  return MoewsResult(score: total, riskLevel: _riskLevel(scores, total));
}
