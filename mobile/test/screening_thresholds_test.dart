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

  test('confidence below 0.5 is INCONCLUSIVE', () {
    final r = mapYamnetToResult(abnormalScore: 0.4);
    expect(r.label, 'INCONCLUSIVE');
  });

  test('mid confidence maps to GREEN', () {
    final r = mapYamnetToResult(abnormalScore: 0.6);
    expect(r.label, 'GREEN');
  });

  test('simulator forceRed returns RED', () {
    final r = simulatorClassify(forceRed: true);
    expect(r.label, 'RED');
    expect(r.source, 'simulator');
  });
}
