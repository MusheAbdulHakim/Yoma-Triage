import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/opera_ce_head_map.dart';
import 'package:yoma_triage/services/opera_ce_mel.dart';
import 'package:yoma_triage/services/screening_model_factory.dart';

void main() {
  test('pack-pending hear_event never returns silent GREEN', () async {
    final result = await PackPendingClassifier('hear_event')
        .classifyPcm16kHzMono(Uint8List(0));
    expect(result.label, 'INCONCLUSIVE');
    expect(result.confidence, 0.0);
    expect(result.modelVersion, 'hear_event-pending');
  });

  test('OPERA-CE head mapper fail-closed mid-band', () {
    final mid = mapOperaCeHeadToResult([0.1, 0.2]);
    expect(mid.label, 'INCONCLUSIVE');
    final red = mapOperaCeHeadToResult([-2.0, 3.0]);
    expect(red.label, 'RED');
    final green = mapOperaCeHeadToResult([3.0, -2.0]);
    expect(green.label, 'GREEN');
  });

  test('OPERA-CE mel shape is 251x64 for 8s audio', () {
    final rng = math.Random(0);
    final samples = List<double>.generate(
      OperaCeMel.targetSamples,
      (_) => (rng.nextDouble() * 2 - 1) * 0.1,
    );
    final mel = OperaCeMel.melForEncoder(samples);
    expect(mel.length, OperaCeMel.melFrames * OperaCeMel.melBins);
    // Min-max normalized
    var lo = mel[0];
    var hi = mel[0];
    for (final v in mel) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    expect(lo, greaterThanOrEqualTo(-1e-5));
    expect(hi, lessThanOrEqualTo(1.0 + 1e-5));
  });
}
