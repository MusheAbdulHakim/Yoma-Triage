// A2: Emergency Referral is always reachable. It is pinned at the top of Home, the
// warnings share one summary banner that opens on tap, and the rest of Home scrolls.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/offline_queue.dart';

import 'helpers/cho_helper.dart';

/// A phone with no signal: every request fails, as offline.
ApiClient _offline() => ApiClient(
      client: MockClient((_) async => throw http.ClientException('no signal')),
      baseUrl: 'http://test.invalid',
    );

/// Reports fixed counts, as a queue with that many referrals in each state would.
class _Queue extends OfflineQueue {
  _Queue({this.failedN = 0, this.staleN = 0, this.expiringN = 0}) {
    // Already known before Home opens, as after an earlier sync. A count that rises while
    // Home is open opens the prompt instead, which these tests don't want.
    needsConfirmationCount.value = staleN;
  }

  final int failedN;
  final int staleN;
  final int expiringN;

  @override
  Future<List<QueuedReferral>> failed() async {
    failedCount.value = failedN;
    return const [];
  }

  @override
  Future<List<QueuedReferral>> needsConfirmation() async {
    needsConfirmationCount.value = staleN;
    return const [];
  }

  @override
  Future<int> noteExpiryWarning({DateTime? now}) async {
    expiringCount.value = expiringN;
    return expiringN;
  }
}

/// Every warning Home can show, at once. The catalog card shows too, because this phone
/// has never synced its catalog.
_Queue _everyWarning() {
  final queue = _Queue(failedN: 2, staleN: 1, expiringN: 3);
  queue.noteRetryWarning(
    'Could not send. A Wi-Fi login page may be in the way. Will retry when there is signal.',
  );
  return queue;
}

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openHome(WidgetTester tester, OfflineQueue queue) async {
  await tester.pumpWidget(
    MaterialApp(home: HomeScreen(api: _offline(), queue: queue, acousticEnabled: false)),
  );
  // Counts and the catalog check arrive asynchronously.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final _button = find.byKey(const Key('home_emergency_referral'));

void _expectFullyVisible(WidgetTester tester, Size size) {
  final rect = tester.getRect(_button);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(size.height), reason: 'Emergency Referral cut off: $rect');
  expect(rect.right, lessThanOrEqualTo(size.width));
  expect(rect.height, greaterThanOrEqualTo(48), reason: 'big enough to tap');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(registeredChoPrefs()));

  for (final size in const [Size(320, 568), Size(360, 640)]) {
    final label = '${size.width.toInt()}×${size.height.toInt()} dp';

    group('at $label with every warning showing', () {
      testWidgets('Emergency Referral is fully visible, and the warnings are one banner',
          (tester) async {
        _screen(tester, size);
        await _openHome(tester, _everyWarning());

        expect(tester.takeException(), isNull, reason: 'no overflow');
        _expectFullyVisible(tester, size);
        expect(find.byKey(const Key('home_warnings_summary')), findsOneWidget);
        // The most urgent warning names the banner; the others wait behind it.
        expect(find.text('2 referrals were NOT sent'), findsOneWidget);
        expect(find.text('4 more warnings. Tap to see all.'), findsOneWidget);
        expect(find.byKey(const Key('home_failed_referrals')), findsNothing);
      });

      testWidgets('with the banner open, Emergency Referral stays put and Home scrolls',
          (tester) async {
        _screen(tester, size);
        await _openHome(tester, _everyWarning());
        final before = tester.getRect(_button);

        await tester.tap(find.byKey(const Key('home_warnings_summary')));
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'no overflow');
        for (final key in const [
          'home_failed_referrals',
          'home_stale_referrals',
          'home_expiring',
          'home_retry_warning',
          'home_catalog_stale',
        ]) {
          expect(find.byKey(Key(key), skipOffstage: false), findsOneWidget, reason: key);
        }
        expect(tester.getRect(_button), before, reason: 'pinned: it does not move');
        _expectFullyVisible(tester, size);

        // The rest of Home is still reachable, by scrolling.
        await tester.scrollUntilVisible(
          find.text('Record Vitals'),
          200,
          scrollable: find.descendant(
            of: find.byKey(const Key('home_scroll')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('Record Vitals'), findsOneWidget);
        expect(tester.getRect(_button), before, reason: 'still pinned after scrolling');
      });

      testWidgets('Emergency Referral can be tapped, and opens the referral', (tester) async {
        _screen(tester, size);
        await _openHome(tester, _everyWarning());
        await tester.tap(find.byKey(const Key('home_warnings_summary')));
        await tester.pump();

        // Hit-tests the centre: fails if anything is drawn over the button.
        await tester.tap(_button);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(ReferralScreen), findsOneWidget);
      });
    });
  }

  group('summary banner', () {
    testWidgets('no warnings, no banner', (tester) async {
      _screen(tester, const Size(360, 640));
      SharedPreferences.setMockInitialValues({
        ...registeredChoPrefs(),
        // A catalog synced just now isn't stale.
        'catalog_synced_at': DateTime.now().toIso8601String(),
      });
      await _openHome(tester, _Queue());
      expect(find.byKey(const Key('home_warnings_summary')), findsNothing);
      _expectFullyVisible(tester, const Size(360, 640));
    });

    testWidgets('one warning says so, and tapping again closes it', (tester) async {
      _screen(tester, const Size(360, 640));
      SharedPreferences.setMockInitialValues({
        ...registeredChoPrefs(),
        'catalog_synced_at': DateTime.now().toIso8601String(),
      });
      await _openHome(tester, _Queue(failedN: 1));
      expect(find.text('1 referral was NOT sent'), findsOneWidget);
      expect(find.text('Tap to see details'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_warnings_summary')));
      await tester.pump();
      expect(find.byKey(const Key('home_failed_referrals')), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_warnings_summary')));
      await tester.pump();
      expect(find.byKey(const Key('home_failed_referrals')), findsNothing);
    });

    testWidgets('urgent warnings come before the rest', (tester) async {
      _screen(tester, const Size(360, 640));
      final queue = _Queue(expiringN: 1, staleN: 1);
      await _openHome(tester, queue);
      // Stale beats expiring and the catalog, whatever order they arrived in.
      expect(find.text('Still needs transport?'), findsOneWidget);
    });
  });
}
