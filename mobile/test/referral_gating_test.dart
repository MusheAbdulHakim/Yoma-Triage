import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/referral_gating.dart';

void main() {
  test('MOEWS RED indicates referral even if acoustic GREEN', () {
    expect(
      referralIndicated(acousticLabel: 'GREEN', moewsRiskLevel: 'RED'),
      isTrue,
    );
  });

  test('acoustic GREEN + MOEWS GREEN does not indicate referral', () {
    expect(
      referralIndicated(acousticLabel: 'GREEN', moewsRiskLevel: 'GREEN'),
      isFalse,
    );
  });

  test('acoustic RED indicates referral (CHO still confirms in UI)', () {
    expect(
      referralIndicated(acousticLabel: 'RED', moewsRiskLevel: 'GREEN'),
      isTrue,
    );
  });

  test('INCONCLUSIVE alone does not indicate unless CHO refer flag', () {
    expect(
      referralIndicated(acousticLabel: 'INCONCLUSIVE', moewsRiskLevel: 'GREEN'),
      isFalse,
    );
    expect(
      referralIndicated(
        acousticLabel: 'INCONCLUSIVE',
        moewsRiskLevel: 'GREEN',
        choReferDespiteInconclusive: true,
      ),
      isTrue,
    );
  });

  test('emergency bypass always indicates', () {
    expect(
      referralIndicated(
        acousticLabel: 'GREEN',
        moewsRiskLevel: 'GREEN',
        emergencyBypass: true,
      ),
      isTrue,
    );
  });

  test('unknown MOEWS with acoustic GREEN does not indicate', () {
    expect(
      referralIndicated(acousticLabel: 'GREEN', moewsRiskLevel: null),
      isFalse,
    );
  });
}
