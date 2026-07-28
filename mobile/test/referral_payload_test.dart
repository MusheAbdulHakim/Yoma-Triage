import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/models/referral.dart';

void main() {
  test('toJson is scores-only', () {
    final json = ReferralRequest(
      clientRequestId: 'x',
      chpsCompoundId: 1,
      facilityId: 1,
      patientHash: 'h',
      emergencyType: 'respiratory_distress',
      vitals: {'systolic_bp': 120},
      aiScreenResult: 'GREEN',
      aiConfidence: 0.6,
      aiModelVersion: 'yamnet-audioset-v0',
    ).toJson();

    expect(json['ai_model_version'], 'yamnet-audioset-v0');
    expect(json.containsKey('audio'), isFalse);
    expect(json.containsKey('embedding'), isFalse);
    expect(json.containsKey('pcm'), isFalse);
  });
}
