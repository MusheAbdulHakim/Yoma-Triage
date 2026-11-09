/// Scenario 8: the backend is killed mid-cascade, and stays down past the tier deadline.
/// The harness runs it with CASCADE_TIER_SECONDS=30, for this test only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

const _tierSeconds = 30;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('the cascade continues after a restart, and the screen follows', (tester) async {
    await tester.setUpCho();

    await tester.openReferralForm();
    await tester.tapOn(find.byKey(const Key('referral_send')));
    await tester.waitFor(find.byKey(const Key('dispatch_status_TIER1_NOTIFIED')), timeout: const Duration(seconds: 30));
    await tester.shot('s8_1_tier1');
    final before = await Host.rows('dispatches');
    expect(before.single['status'], 'TIER1_NOTIFIED');

    await Host.killBackend();
    await tester.wait(const Duration(seconds: _tierSeconds + 5));
    await tester.shot('s8_2_backend_down');
    // A4: plain words and a next step, not the network error.
    expect(find.textContaining('Server unreachable'), findsOneWidget);
    for (final raw in ['SocketException', 'ClientException', 'Polling']) {
      expect(find.textContaining(raw), findsNothing, reason: raw);
    }

    // Unreachable: the banner and contacts come first (round 5), so on a short screen the
    // timeline is further down.
    await tester.reveal(find.byKey(const Key('dispatch_status_TIER1_NOTIFIED')));
    expect(find.byKey(const Key('dispatch_status_TIER1_NOTIFIED')), findsOneWidget, reason: 'last known status stays');

    final restarted = Stopwatch()..start();
    await Host.startBackend();
    await tester.waitFor(
      find.byKey(const Key('dispatch_status_TIER2_NOTIFIED')),
      timeout: const Duration(seconds: 30),
      reason: 'the overdue tier to fire after the restart',
    );
    await Host.metric('restart_to_tier2_on_screen_ms', restarted.elapsedMilliseconds);
    await tester.shot('s8_3_tier2_after_restart');

    // At the end of the cascade the banner and contacts come first (round 5); the
    // timeline, with its FAILED step, is further down on a short screen.
    await tester.waitFor(
      find.text('No driver has accepted. Call one now.'),
      timeout: const Duration(seconds: _tierSeconds + 30),
      reason: 'the cascade to keep going to the end',
    );
    await tester.waitFor(find.byKey(const Key('manual_contacts')));
    await tester.shot('s8_4_failed_with_contacts');
    await tester.reveal(find.byKey(const Key('dispatch_status_FAILED')));
    expect(find.byKey(const Key('dispatch_status_FAILED')), findsOneWidget);

    final messages = await Host.rows('outbox');
    for (final m in messages) {
      await Host.note('SMS ${m['purpose']} to ${m['recipient']}: ${m['status']}');
    }
    final offers = messages.where((m) => m['purpose'] == 'driver_offer').map((m) => m['recipient']);
    expect(
      offers.toList()..sort(),
      ['+233240000001', '+233240000002', '+233240000003'],
      reason: 'each driver offered once, with no repeat after the restart',
    );
    expect(
      messages.where((m) => m['purpose'] == 'cho_escalation').map((m) => m['recipient']),
      contains(registeredCho),
    );
  });
}
