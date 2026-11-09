/// Scenario 6: real airplane mode. The referral queues, and Call and SMS open the phone's
/// own dialler and messaging app with the right number and text. When signal returns the
/// queue sends by itself: after a Call or SMS the CHO is asked first (B2), and without
/// one the screen moves on to drivers notified (A4).
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
    final confirm = find.byKey(const Key('referral_send'));
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

    // Signal returns while the CHO is still looking at this screen. Nothing is tapped.
    await Host.airplane(false);
    var received = false;
    for (var i = 0; i < 40 && !received; i++) {
      await tester.wait(const Duration(seconds: 1));
      received = (await Host.rows('referrals')).isNotEmpty;
    }
    expect(received, isTrue, reason: 'the queue sends by itself when signal returns');

    // B2: the CHO already used Call or SMS, so drivers are not told until the CHO says
    // transport is still needed, however young the referral is.
    final held = await Host.rows('referrals');
    expect(held.single['status'], 'AWAITING_CONFIRMATION', reason: 'held for the CHO');
    expect(await Host.rows('dispatches'), isEmpty, reason: 'nobody told before the CHO answers');
    // A4: the queued screen follows the send to the question.
    await tester.waitFor(
      find.text('Still needs transport?'),
      timeout: const Duration(seconds: 20),
      reason: 'the screen to follow the automatic send to the question',
    );
    expect(find.textContaining('You used Call or SMS'), findsOneWidget);
    await tester.wait(const Duration(seconds: 2));
    await tester.shot('s6_6_manual_contact_question');

    final sendNow = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('stale_send_now_'),
    );
    final id = (tester.widget(sendNow).key! as ValueKey<String>)
        .value
        .substring('stale_send_now_'.length);
    await tester.tapOn(sendNow);
    await tester.tapOn(find.byKey(Key('stale_confirm_$id')));
    await tester.waitFor(find.text('TIER1_NOTIFIED'), timeout: const Duration(seconds: 20));
    expect(await Host.rows('dispatches'), hasLength(1));
    await tester.shot('s6_7_send_now_dispatched');

    // A4 with no Call or SMS: a second referral queues offline and, when signal returns,
    // the screen moves on to drivers notified by itself.
    await tester.tapOn(find.text('Back to Home'));
    await tester.waitFor(find.byKey(const Key('home_emergency_referral')));
    await Host.airplane(true);
    await tester.wait(const Duration(seconds: 2));
    await tester.openReferralForm();
    await tester.tapOn(find.byKey(const Key('referral_skip_vitals')));
    await tester.waitFor(find.text('Referral Queued'), timeout: const Duration(seconds: 45));
    await Host.airplane(false);
    await tester.waitFor(
      find.text('TIER1_NOTIFIED'),
      timeout: const Duration(seconds: 60),
      reason: 'the screen to show drivers notified after the automatic send',
    );
    expect(find.textContaining('Drivers have not been notified'), findsNothing);
    expect(await Host.rows('dispatches'), hasLength(2));
    await tester.shot('s6_8_dispatched_by_itself');

    final server = '${await Host.rows('referrals')} ${await Host.rows('outbox')}';
    expect(server, isNot(contains('Zebra')), reason: 'the name never reaches the server');
  });
}
