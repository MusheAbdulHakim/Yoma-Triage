import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/advisory_hr.dart';

void main() {
  test('plausible HR and SpO2 bounds', () {
    const ok = AdvisoryHrReading(
      heartRateBpm: 88,
      source: AdvisoryHrSource.blePulseOx,
      spo2Percent: 97,
    );
    expect(ok.isPlausibleHr, isTrue);
    expect(ok.isPlausibleSpo2, isTrue);
    expect(ok.confirmMessage, contains('88'));
    expect(ok.confirmMessage, contains('advisory'));

    const badHr = AdvisoryHrReading(
      heartRateBpm: 10,
      source: AdvisoryHrSource.contactPpg,
    );
    expect(badHr.isPlausibleHr, isFalse);
  });
}
