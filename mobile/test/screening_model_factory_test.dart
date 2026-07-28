import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/screening_model_factory.dart';

void main() {
  test('pack-pending classifiers never return silent GREEN', () async {
    for (final id in ['hear_event', 'opera_ce']) {
      final result =
          await PackPendingClassifier(id).classifyPcm16kHzMono(Uint8List(0));
      expect(result.label, 'INCONCLUSIVE');
      expect(result.confidence, 0.0);
      expect(result.modelVersion, '$id-pending');
    }
  });
}
