/// Scenario 6: real airplane mode. The referral queues, and Call and SMS open the phone's
/// own dialler and messaging app with the right number and text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

const _patient = 'Zebra Testpatient';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('queues offline, and Call and SMS open with the right details', (tester) async {
    await tester.setUpCho();
    // Contacts are saved in the background after setup, and must be there before signal goes.
    await tester.wait(const Duration(seconds: 3));

    await Host.airplane(true);
    addTearDown(() => Host.airplane(false));
    await tester.wait(const Duration(seconds: 2));

    await tester.openReferralForm();
    await tester.fillPatientName(_patient);
    await tester.fillVitals('referral');
    final confirm = find.text('Confirm Referral');
    await tester.tapOn(confirm);

    await tester.waitFor(find.text('Referral Queued'), timeout: const Duration(seconds: 45));
    expect(find.textContaining('Drivers have not been notified'), findsOneWidget);
    await tester.shot('s6_1_queued');

    final panel = find.byKey(const Key('manual_contacts'));
    await tester.reveal(panel);
    await tester.shot('s6_2_contacts');

    // Offline retry keeps it, with no error that could read as sent.
    await tester.tapOn(find.text('Retry sync'));
    await tester.waitFor(find.textContaining('Still waiting for coverage'));
    await tester.shot('s6_3_retry_offline');

    final call = find.byKey(const Key('call_$motorKingDriver'));
    await tester.tapOn(call);
    final dialler = await Host.call('/external-app', {'name': 's6_4_dialler'}) as Map;
    await Host.note('Call opened ${dialler['package']}: ${dialler['text']}');
    expect(dialler['package'], isNot('gh.yomatriage.yoma_triage'), reason: 'dialler did not open');
    final digits = (dialler['text'] as String).replaceAll(RegExp(r'[^0-9]'), '');
    expect(digits, contains('240000001'), reason: 'the driver\'s number');
    await tester.wait(const Duration(seconds: 1));

    final sms = find.byKey(const Key('sms_$motorKingDriver'));
    await tester.tapOn(sms);
    final messaging = await Host.call('/external-app', {'name': 's6_5_messaging'}) as Map;
    await Host.note('SMS opened ${messaging['package']}: ${messaging['text']}');
    expect(messaging['package'], isNot('gh.yomatriage.yoma_triage'), reason: 'messaging did not open');
    final text = messaging['text'] as String;
    expect(text, contains('Emergency transport needed at $compoundName'));
    expect(text, isNot(contains('Zebra')), reason: 'no patient name');
    await tester.wait(const Duration(seconds: 1));

    // Signal returns while the CHO is still looking at this screen.
    await Host.airplane(false);
    var sent = false;
    for (var i = 0; i < 40 && !sent; i++) {
      await tester.wait(const Duration(seconds: 1));
      sent = (await Host.rows('dispatches')).isNotEmpty;
    }
    expect(sent, isTrue, reason: 'the queue sends by itself when signal returns');
    // A4: nothing is tapped. The queued screen follows the send to the dispatch screen.
    await tester.waitFor(
      find.text('TIER1_NOTIFIED'),
      timeout: const Duration(seconds: 20),
      reason: 'the screen to show drivers notified after the automatic send',
    );
    expect(find.textContaining('Drivers have not been notified'), findsNothing);
    await tester.shot('s6_6_dispatched_by_itself');

    final server = '${await Host.rows('referrals')} ${await Host.rows('outbox')}';
    expect(server, isNot(contains('Zebra')), reason: 'the name never reaches the server');
  });
}
