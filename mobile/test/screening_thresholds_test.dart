import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/screening_result.dart';

void main() {
  test('confidence above 0.7 maps abnormal to RED', () {
    final r = mapYamnetToResult(abnormalScore: 0.82);
    expect(r.label, 'RED');
    expect(r.source, 'yamnet');
  });

  test('YAMNet result identifies the classifier version', () {
    final r = mapYamnetToResult(abnormalScore: 0.82);
    expect(r.modelVersion, 'yamnet-audioset-v0');
  });

  test('low abnormal score maps to GREEN (advisory)', () {
    final r = mapYamnetToResult(abnormalScore: 0.4);
    expect(r.label, 'GREEN');
    expect(r.reason, isNot(contains('Normal breathing pattern')));
  });

  test('mid-band is INCONCLUSIVE — never labeled normal', () {
    final r = mapYamnetToResult(abnormalScore: 0.6);
    expect(r.label, 'INCONCLUSIVE');
    expect(r.reason.toLowerCase(), isNot(contains('normal breathing')));
  });

  test('simulator forceRed returns RED', () {
    final r = simulatorClassify(forceRed: true);
    expect(r.label, 'RED');
    expect(r.source, 'simulator');
  });
}
