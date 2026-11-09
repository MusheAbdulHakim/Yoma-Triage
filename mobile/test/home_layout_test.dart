import 'dart:async';

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
import 'package:yoma_triage/theme/yoma_theme.dart';

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

Future<void> _openHome(
  WidgetTester tester,
  OfflineQueue queue, {
  bool acoustic = false,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildYomaTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HomeScreen(api: _offline(), queue: queue, acousticEnabled: acoustic),
    ),
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
          find.text('Record vitals'),
          200,
          scrollable: find.descendant(
            of: find.byKey(const Key('home_scroll')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('Record vitals'), findsOneWidget);
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

  group('layout (Home layout update)', () {
    final checkBreathing = find.byKey(const Key('home_check_breathing'));
    final recordVitals = find.byKey(const Key('home_record_vitals'));

    testWidgets(
        'acoustic mode: Emergency referral first, then Check breathing, '
        'directly under the top bar', (tester) async {
      _screen(tester, const Size(360, 640));
      await _openHome(tester, _Queue(), acoustic: true);

      expect(checkBreathing, findsOneWidget);
      final emergency = tester.getRect(_button);
      final breathing = tester.getRect(checkBreathing);
      expect(emergency.bottom, lessThanOrEqualTo(breathing.top), reason: 'order');
      // Normal spacing, no large empty area between them.
      expect(breathing.top - emergency.bottom, lessThanOrEqualTo(16));
      // Emergency referral sits under the top bar, not pushed down the screen.
      expect(emergency.top, lessThan(100));
      // Still the largest action.
      expect(emergency.height, greaterThan(breathing.height));
      expect(find.text('Advisory'), findsOneWidget);
    });

    testWidgets('MOEWS-only mode: no Check breathing, and no gap where it would be',
        (tester) async {
      _screen(tester, const Size(360, 640));
      await _openHome(tester, _Queue(), acoustic: false);

      expect(checkBreathing, findsNothing);
      expect(find.text('Check breathing'), findsNothing);
      expect(recordVitals, findsOneWidget);
      final emergency = tester.getRect(_button);
      final vitals = tester.getRect(recordVitals);
      expect(emergency.bottom, lessThanOrEqualTo(vitals.top), reason: 'order');
      expect(vitals.top - emergency.bottom, lessThanOrEqualTo(16), reason: 'no gap');
      expect(emergency.height, greaterThan(vitals.height));
    });

    for (final acoustic in const [false, true]) {
      final mode = acoustic ? 'acoustic' : 'MOEWS-only';
      testWidgets(
          '$mode: at 320 dp and 130% text, with every warning showing and open, '
          'Emergency referral is fully visible and tappable', (tester) async {
        const size = Size(320, 568);
        _screen(tester, size);
        await _openHome(tester, _everyWarning(), acoustic: acoustic, textScale: 1.3);
        expect(tester.takeException(), isNull, reason: 'no overflow');
        _expectFullyVisible(tester, size);

        await tester.tap(find.byKey(const Key('home_warnings_summary')));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'no overflow when open');
        _expectFullyVisible(tester, size);

        await tester.tap(_button);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(ReferralScreen), findsOneWidget);
      });
    }

    testWidgets('the strip is navy for a failure and light while only waiting', (tester) async {
      _screen(tester, const Size(360, 640));
      SharedPreferences.setMockInitialValues({
        ...registeredChoPrefs(),
        'catalog_synced_at': DateTime.now().toIso8601String(),
      });
      await _openHome(tester, _Queue(failedN: 1));
      Material strip() => tester.widget<Material>(find.byKey(const Key('home_warnings_summary')));
      expect(strip().color, YomaColors.navy);

      await tester.pumpWidget(const SizedBox()); // a fresh Home, with a fresh queue
      await _openHome(tester, _Queue(expiringN: 1));
      expect(strip().color, YomaColors.surface);
    });

    testWidgets('the clinic name shows under Yoma Care', (tester) async {
      _screen(tester, const Size(360, 640));
      await _openHome(tester, _Queue());
      expect(find.text('Yoma Care'), findsOneWidget);
      expect(find.byKey(const Key('home_clinic_name')), findsOneWidget);
    });
  });

  testWidgets('Offline pill shows only while the phone has no network', (tester) async {
    _screen(tester, const Size(360, 640));
    final online = StreamController<bool>();
    addTearDown(online.close);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: buildYomaTheme(),
      home: HomeScreen(
          api: _offline(), queue: _Queue(), acousticEnabled: false, online: online.stream),
    ));
    online.add(true);
    await tester.pump();
    expect(find.text('Offline'), findsNothing);

    online.add(false);
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Offline\\. Referrals are saved')), findsOneWidget);
    // Emergency referral stays first and whole.
    _expectFullyVisible(tester, const Size(360, 640));

    online.add(true);
    await tester.pump();
    expect(find.text('Offline'), findsNothing);
    handle.dispose();
  });
}
