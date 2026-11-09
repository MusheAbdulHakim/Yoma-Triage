/// A2, on a device: Emergency Referral stays fully visible and tappable on Home with every
/// warning showing at once. The harness runs this at 320×568 dp ('banners') and at the
/// device's own size ('banners_native'), which on the API 24 AVD is 360×640 dp.
///
/// Each warning's real counter on OfflineQueue.shared is set directly, so no failed or
/// stale referrals have to be built up first. The catalog warning is real: the backend is
/// stopped and the catalog's sync time cleared, then the app restarts, so it can't sync.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/config.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/services/offline_queue.dart';

import 'support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('Emergency Referral stays on screen and tappable with every warning up', (tester) async {
    await tester.setUpCho();
    await tester.wait(const Duration(seconds: 3));

    // A catalog that has never synced, and a server that can't be reached.
    await Host.killBackend();
    addTearDown(Host.startBackend);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(CatalogConfig.syncedAtPrefsKey);
    await prefs.remove(CatalogConfig.catalogVersionPrefsKey);
    await tester.startApp();
    await tester.waitFor(find.byKey(const Key('home_emergency_referral')));
    // Let Home's own refresh of the counts finish first, so it can't overwrite them.
    await tester.wait(const Duration(seconds: 3));

    final queue = OfflineQueue.shared;
    final button = find.byKey(const Key('home_emergency_referral'));

    // On Home a rising stale count opens the prompt at once. From another screen it
    // leaves a warning on Home instead, so raise it from there.
    await tester.tapOn(button);
    await tester.waitFor(find.byType(BackButton));
    queue.needsConfirmationCount.value = 1;
    await tester.tapOn(find.byType(BackButton));
    await tester.waitFor(find.byKey(const Key('home_emergency_referral')));
    queue.failedCount.value = 2;
    queue.expiringCount.value = 3;
    queue.retryWarning.value = 'Could not send. Will retry when there is signal.';
    await tester.wait(const Duration(seconds: 1));

    final view = tester.view;
    final screenBottom =
        (view.physicalSize.height - view.padding.bottom) / view.devicePixelRatio;
    final screenRight = view.physicalSize.width / view.devicePixelRatio;
    final screenTop = view.padding.top / view.devicePixelRatio;

    Future<void> check(String state) async {
      final rect = tester.getRect(button);
      await Host.note(
        'Home, $state: Emergency Referral at ${rect.top.round()}–${rect.bottom.round()} dp; '
        'screen ${screenTop.round()}–${screenBottom.round()} dp',
      );
      await tester.shot('s9_banners_$state');
      expect(rect.top, greaterThanOrEqualTo(screenTop), reason: '$state: above the screen');
      expect(rect.bottom, lessThanOrEqualTo(screenBottom), reason: '$state: cut off');
      expect(rect.right, lessThanOrEqualTo(screenRight), reason: '$state: cut off at the side');
    }

    expect(find.byKey(const Key('home_warnings_summary')), findsOneWidget);
    expect(find.textContaining('more warnings'), findsOneWidget);
    await check('all_warnings_closed');

    await tester.tapOn(find.byKey(const Key('home_warnings_summary')));
    await tester.wait(const Duration(milliseconds: 500));
    for (final key in const [
      'home_failed_referrals',
      'home_stale_referrals',
      'home_expiring',
      'home_retry_warning',
      'home_catalog_stale',
    ]) {
      expect(find.byKey(Key(key), skipOffstage: false), findsOneWidget, reason: key);
    }
    await check('all_warnings_open');

    // A real tap, through the hit test: nothing may cover the button.
    await tester.tap(button);
    await tester.waitFor(find.byType(ReferralScreen), reason: 'the referral to open');
  });
}
