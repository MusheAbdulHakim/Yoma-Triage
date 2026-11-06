import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/moews_calculator.dart';

/// The same cases run in tests/test_moews.py, so the server and the app can't
/// disagree about a patient.
void main() {
  final cases = jsonDecode(
    File('../tests/fixtures/moews_cases.json').readAsStringSync(),
  ) as List<dynamic>;

  for (final raw in cases) {
    final testCase = raw as Map<String, dynamic>;
    final vitals = testCase['vitals'] as Map<String, dynamic>;
    test(testCase['name'] as String, () {
      final result = calculateMoews(
        sbp: vitals['systolic_bp'] as int?,
        dbp: vitals['diastolic_bp'] as int?,
        hr: vitals['heart_rate'] as int?,
        rr: vitals['respiratory_rate'] as int?,
        temp: (vitals['temperature'] as num?)?.toDouble(),
        spo2: vitals['spo2'] as int?,
        consciousness: vitals['consciousness_level'] as String?,
      );
      expect(result.riskLevel, testCase['risk']);
      expect(result.score, testCase['score']);
      expect(result.missingVitals, testCase['missing']);
    });
  }
}
