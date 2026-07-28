import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/moews_calculator.dart';

void main() {
  test('normal vitals green', () {
    final r = calculateMoews(
      sbp: 120,
      dbp: 80,
      hr: 80,
      rr: 18,
      temp: 37.0,
      spo2: 98,
      consciousness: 'A',
    );
    expect(r.score, 0);
    expect(r.riskLevel, 'GREEN');
  });

  test('critical vitals red', () {
    final r = calculateMoews(
      sbp: 70,
      dbp: 50,
      hr: 140,
      rr: 35,
      temp: 39.5,
      spo2: 85,
      consciousness: 'V',
    );
    expect(r.score, greaterThanOrEqualTo(5));
    expect(r.riskLevel, 'RED');
  });

  test('moderate vitals yellow', () {
    final r = calculateMoews(
      sbp: 120,
      dbp: 80,
      hr: 80,
      rr: 25,
      temp: 37.0,
      spo2: 98,
      consciousness: 'A',
    );
    expect(r.score, isNotNull);
    expect(r.score!, inInclusiveRange(1, 4));
    expect(r.riskLevel, 'YELLOW');
  });

  test('null required vital is UNKNOWN', () {
    final r = calculateMoews(
      sbp: null,
      dbp: 80,
      hr: 80,
      rr: 18,
      temp: 37.0,
      spo2: 98,
      consciousness: 'A',
    );
    expect(r.riskLevel, 'UNKNOWN');
    expect(r.score, isNull);
  });

  test('single param score 3 is red', () {
    final r = calculateMoews(
      sbp: 70,
      dbp: 80,
      hr: 80,
      rr: 18,
      temp: 37.0,
      spo2: 98,
      consciousness: 'A',
    );
    expect(r.score, 3);
    expect(r.riskLevel, 'RED');
  });

  test('abnormal HR alone is score 3 and flagged', () {
    final r = calculateMoews(
      sbp: 120,
      dbp: 80,
      hr: 140,
      rr: 18,
      temp: 37.0,
      spo2: 98,
      consciousness: 'A',
    );
    expect(r.hrScore, 3);
    expect(r.hrAbnormal, isTrue);
    expect(r.riskLevel, 'RED');
  });

  test('borderline HR is score 1 and flagged', () {
    final r = calculateMoews(
      sbp: 120,
      dbp: 80,
      hr: 120,
      rr: 18,
      temp: 37.0,
      spo2: 98,
      consciousness: 'A',
    );
    expect(r.hrScore, 1);
    expect(r.hrAbnormal, isTrue);
    expect(r.riskLevel, 'YELLOW');
  });
}
