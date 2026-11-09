/// Scenario 4: full vitals to dispatch, then driver accept and arrival over USSD.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('each status change reaches the screen, and SMS go to the right roles',
      (tester) async {
    await tester.setUpCho();

    await tester.tapOn(find.text('Record vitals'));
    await tester.waitFor(find.byKey(const Key('vitals_sbp')));
    await tester.fillVitals('vitals');
    await tester.shot('s4_1_vitals');
    await tester.tapOn(find.byKey(const Key('vitals_see_result')));
    await tester.waitFor(find.text('Result'));
    await tester.shot('s4_2_result');

    await tester.tapOn(find.text('Confirm Referral'));
    await tester.chooseFacility();
    await tester.chooseEmergency();
    await tester.fillPatientName('Zebra Testpatient');
    await tester.shot('s4_3_form');

    // Spec timing: from tapping Send referral to the screen showing drivers notified.
    final confirm = find.byKey(const Key('referral_send'));
    await tester.closeKeyboard();
    await tester.reveal(confirm);
    await tester.wait(const Duration(milliseconds: 300));
    final stopwatch = Stopwatch()..start();
    await tester.tap(confirm);
    await tester.waitFor(find.byKey(const Key('dispatch_status_TIER1_NOTIFIED')), timeout: const Duration(seconds: 30));
    await Host.metric('confirm_to_notified_ms_debug', stopwatch.elapsedMilliseconds);
    await tester.shot('s4_4_tier1');

    final dispatchId = tester.dispatchIdOnScreen();
    await Host.note('Dispatch #$dispatchId');

    final accept = await ussdAccept(motorKingDriver, dispatchId);
    await Host.note('USSD accept replied: "$accept"');
    expect(accept, contains('Accepted'));
    await tester.waitFor(find.byKey(const Key('dispatch_status_HOSPITAL_NOTIFIED')), timeout: const Duration(seconds: 15));
    await tester.waitFor(find.textContaining('Driver: Ibrahim'));
    await tester.shot('s4_5_accepted');

    final arrival = await ussdArrival(motorKingDriver);
    await Host.note('USSD arrival replied: "$arrival"');
    expect(arrival, contains('Arrival confirmed'));
    await tester.waitFor(find.byKey(const Key('dispatch_status_COMPLETED')), timeout: const Duration(seconds: 15));
    await tester.shot('s4_6_completed');

    // Let the sender reach everything, then check who was told what.
    await tester.wait(const Duration(seconds: 6));
    final messages = await Host.rows('outbox');
    for (final m in messages) {
      await Host.note('SMS ${m['purpose']} to ${m['recipient']}: ${m['status']}');
    }
    String? recipientOf(String purpose) =>
        messages.where((m) => m['purpose'] == purpose).firstOrNull?['recipient'] as String?;

    final offers = messages
        .where((m) => m['purpose'] == 'driver_offer')
        .map((m) => m['recipient'])
        .toSet();
    expect(offers, {'+233240000001', '+233240000002'}, reason: 'the Motor-King drivers');
    expect(recipientOf('hospital_pre_arrival'), facilityPhone);
    expect(recipientOf('cho_arrival'), registeredCho, reason: 'the CHO who sent it');
    expect(
      messages.where((m) => m['purpose'] == 'cho_arrival').length,
      1,
      reason: 'a routine update goes only to the sender',
    );

    final everything = messages.map((m) => m['body']).join(' ');
    expect(everything, isNot(contains('Zebra')), reason: 'the name never leaves the phone');
    final referrals = await Host.rows('referrals');
    expect(referrals.toString(), isNot(contains('Zebra')));

    // The dispatch log, as the demo reads it: who was sent what, with mock SMS.
    final logResponse = await http
        .get(Uri.parse('$backendUrl/api/v1/dispatch/$dispatchId/logs'))
        .timeout(const Duration(seconds: 15));
    expect(logResponse.statusCode, 200);
    final body = jsonDecode(logResponse.body);
    final logs = ((body is Map ? body['logs'] : body) as List).cast<Map<String, dynamic>>();
    for (final entry in logs) {
      await Host.note(
        'Dispatch log: ${entry['action']} role=${entry['target_role']} '
        'to=${entry['target_phone']} ${entry['response']}',
      );
    }
    final roles = logs.map((entry) => entry['target_role']).toSet();
    expect(roles, containsAll(['driver', 'hospital', 'cho']));
  });
}
