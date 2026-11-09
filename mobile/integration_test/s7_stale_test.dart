/// Scenario 7: stale referrals. The harness runs the backend with STALE_AFTER_MINUTES=1,
/// for this test only. The threshold is the server's, so the app isn't changed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

Finder _keyStarting(String prefix) => find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(prefix),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('the prompt appears, and each answer does the right thing on the server',
      (tester) async {
    await tester.setUpCho();
    await tester.wait(const Duration(seconds: 3));

    await Host.airplane(true);
    addTearDown(() => Host.airplane(false));
    await tester.wait(const Duration(seconds: 2));

    const answers = 3;
    for (var i = 0; i < answers; i++) {
      await tester.openReferralForm();
      await tester.tapOn(find.byKey(const Key('referral_send')));
      await tester.waitFor(find.byKey(const Key('queued_referral')), timeout: const Duration(seconds: 45));
      await tester.tapOn(find.text('Back to Home'));
      await tester.waitFor(find.byKey(const Key('home_emergency_referral')));
    }
    await tester.shot('s7_1_three_queued');

    await tester.wait(const Duration(seconds: 70));
    await Host.airplane(false);

    // Nothing is tapped: the sync and the prompt both come from signal returning.
    final stopwatch = Stopwatch()..start();
    await tester.waitFor(
      find.text('Still needs transport?'),
      timeout: const Duration(seconds: 60),
      reason: 'the stale prompt to open after reconnecting',
    );
    await Host.metric('reconnect_to_prompt_ms', stopwatch.elapsedMilliseconds);
    await tester.waitFor(_keyStarting('stale_cancel_'));
    await tester.wait(const Duration(seconds: 3));
    await tester.shot('s7_2_prompt');
    expect(find.text('1 of $answers'), findsOneWidget, reason: 'one at a time');

    var stored = await Host.rows('referrals');
    expect(stored, hasLength(answers), reason: 'all three reached the server');
    for (final r in stored) {
      expect(r['status'], 'AWAITING_CONFIRMATION');
      expect(r['queue_age_seconds'], greaterThan(60));
    }
    expect(await Host.rows('dispatches'), isEmpty, reason: 'nobody told before the CHO answers');

    Future<void> answer(String action) async {
      final option = _keyStarting('stale_${action}_').first;
      final id = (tester.widget(option).key! as ValueKey<String>)
          .value
          .substring('stale_${action}_'.length);
      // One tap answers: the sheet then shows the next one, or closes.
      await tester.tapOn(find.byKey(Key('stale_${action}_$id')));
      await tester.waitUntilGone(find.byKey(Key('stale_cancel_$id')));
    }

    await answer('already_handled');
    await answer('cancel');
    await tester.shot('s7_3_two_answered');
    await answer('send_now');
    await tester.waitFor(find.byKey(const Key('dispatch_status_TIER1_NOTIFIED')), timeout: const Duration(seconds: 20));
    await tester.shot('s7_4_send_now_dispatched');

    stored = await Host.rows('referrals');
    for (final r in stored) {
      await Host.note('Referral ${r['id']}: ${r['status']}, age ${r['queue_age_seconds']} s');
    }
    final statuses = stored.map((r) => r['status']).toList()..sort();
    expect(statuses, ['CANCELLED', 'CONFIRMED', 'MANUALLY_HANDLED']);

    final dispatches = await Host.rows('dispatches');
    expect(dispatches, hasLength(1), reason: 'only Send now dispatches');
    final sentReferral = stored.singleWhere((r) => r['status'] == 'CONFIRMED');
    expect(dispatches.single['referral_id'], sentReferral['id']);

    final offers = (await Host.rows('outbox')).where((m) => m['purpose'] == 'driver_offer');
    expect(offers, isNotEmpty);
    expect(offers.every((m) => m['dispatch_id'] == dispatches.single['id']), isTrue);

    final audit = (await Host.rows('audit')).map((a) => a['action']).toSet();
    expect(audit, containsAll(['referral_already_handled', 'referral_cancel', 'referral_send_now']));
  });
}

extension on WidgetTester {
  Future<void> waitUntilGone(Finder finder) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      await pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isEmpty) return;
    }
    throw TestFailure('Still on screen: $finder');
  }
}
