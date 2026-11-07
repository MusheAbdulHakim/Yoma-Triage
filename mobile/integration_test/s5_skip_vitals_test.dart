/// Scenario 5: skip vitals dispatches with only the emergency type and facility.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('dispatches, and the hospital is told vitals were not taken', (tester) async {
    await tester.setUpCho();

    await tester.openReferralForm();
    await tester.shot('s5_1_form');
    await tester.tapOn(find.byKey(const Key('referral_skip_vitals')));
    await tester.waitFor(find.text('TIER1_NOTIFIED'), timeout: const Duration(seconds: 30));
    await tester.shot('s5_2_tier1');

    final accept = await ussd(motorKingDriver, '1');
    expect(accept, contains('Accepted'));
    await tester.waitFor(find.text('HOSPITAL_NOTIFIED'), timeout: const Duration(seconds: 15));
    await tester.shot('s5_3_accepted');

    final messages = await Host.rows('outbox');
    final notice = messages.singleWhere((m) => m['purpose'] == 'hospital_pre_arrival');
    await Host.note('Hospital notice:\n${notice['body']}');
    expect(notice['recipient'], facilityPhone);
    expect(notice['body'], contains('Vitals not taken'));

    final referral = (await Host.rows('referrals')).single;
    await Host.note('Stored vitals: ${referral['vitals_json']}');
  });
}
