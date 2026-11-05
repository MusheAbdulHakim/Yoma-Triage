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

  test('score below 0.5 is INCONCLUSIVE per spec 7.1.1, never GREEN', () {
    for (final score in [0.0, 0.1, 0.4, 0.499]) {
      final r = mapYamnetToResult(abnormalScore: score);
      expect(r.label, 'INCONCLUSIVE', reason: 'score $score');
      expect(r.reason, contains('use clinical judgment'));
    }
  });

  test('YAMNet mapping can never return GREEN', () {
    for (var i = 0; i <= 100; i++) {
      expect(mapYamnetToResult(abnormalScore: i / 100).label, isNot('GREEN'));
    }
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
