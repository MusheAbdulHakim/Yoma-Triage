/// Scenario 9, the worst case for Home on a small screen: the warning banners that appear when
/// things are going wrong, stacked up. Home doesn't scroll, so this checks that Emergency
/// Referral can still be reached. Each banner's real count is set directly, so no failed
/// referrals have to be built up first. Only meaningful at 320 dp: the harness runs it there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yoma_triage/services/offline_queue.dart';

import 'support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('Emergency Referral stays on screen with every banner up', (tester) async {
    await tester.setUpCho();
    await tester.wait(const Duration(seconds: 3));

    final queue = OfflineQueue.shared;
    final view = tester.view;
    final screenBottom = (view.physicalSize.height - view.padding.bottom) / view.devicePixelRatio;
    final button = find.widgetWithText(OutlinedButton, 'Emergency Referral');

    Future<double> measure(String name, void Function() raise) async {
      raise();
      await tester.wait(const Duration(seconds: 1));
      await tester.shot('s9_banners_$name');
      final bottom = tester.getRect(button).bottom;
      final hidden = (bottom - screenBottom).clamp(0.0, double.infinity);
      await Host.note(
        'Home with $name: Emergency Referral ends at ${bottom.round()} dp, '
        'screen ends at ${screenBottom.round()} dp, ${hidden.round()} dp hidden',
      );
      return hidden;
    }

    await measure('none', () {});

    // On Home this count opens the stale prompt straight away. From another screen, the app
    // leaves a card on Home instead, so raise it from there.
    await tester.tapOn(button);
    await tester.waitFor(find.byType(BackButton));
    queue.needsConfirmationCount.value = 1;
    await tester.tapOn(find.byType(BackButton));
    await tester.waitFor(find.text('Community Health Officer'));
    await measure('1_stale', () {});

    await measure('2_plus_failed', () => queue.failedCount.value = 1);
    await measure('3_plus_expiring', () => queue.expiringCount.value = 1);
    final hidden = await measure(
      '4_plus_retry_warning',
      () => queue.retryWarning.value = 'Could not send. Will retry when there is signal.',
    );

    expect(hidden, 0, reason: 'Emergency Referral is cut off, and Home does not scroll');
  });
}
