import 'helpers/cho_helper.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';
import 'package:yoma_triage/services/contacts_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';

void main() {
  testWidgets('shows honest queued state without a driver assignment', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QueuedReferralScreen(clientRequestId: 'request-123'),
      ),
    );

    expect(
      find.text(
        'Referral saved on this device. Drivers have not been notified yet. '
        'They will be contacted when this phone has coverage.',
      ),
      findsOneWidget,
    );
    // The raw request id is a debug detail, shown only in test builds.
    expect(find.textContaining('Request:'), findsNothing);
    expect(find.textContaining('request-123'), findsNothing);
    expect(find.text('Retry sync'), findsOneWidget);
    expect(find.textContaining('Driver:'), findsNothing);
  });

  _callFirstTests();
}

void _callFirstTests() {
  testWidgets('the first Call row is on screen at 360×640 without scrolling, above Retry sync',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ...registeredChoPrefs(),
      ContactsStore.prefsKey: jsonEncode({
        'compound_id': 1,
        'drivers': [
          {'name': 'Ibrahim', 'phone': '+233240000001', 'is_motor_king': true},
          {'name': 'Musah', 'phone': '+233240000002', 'is_motor_king': true},
        ],
        'facilities': [
          {'id': 1, 'name': 'Tamale Teaching Hospital', 'phone': '+233240000200'},
        ],
      }),
      ContactsStore.updatedAtPrefsKey: DateTime.now().toUtc().toIso8601String(),
    });
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 72);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildYomaTheme(),
      home: QueuedReferralScreen(
          clientRequestId: 'request-123', facilityId: 1, launcher: (_) async => true),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final call = find.byKey(const Key('call_+233240000001'));
    expect(call.hitTestable(), findsOneWidget, reason: 'visible without scrolling');
    final help = tester.getRect(find.byKey(const Key('queued_help')));
    expect(tester.getRect(call).top, greaterThan(help.bottom));
    // The explanation and Retry sync come after the contacts.
    final retry = find.text('Retry sync', skipOffstage: false);
    await tester.scrollUntilVisible(retry, 200, scrollable: find.byType(Scrollable).first);
    expect(tester.getRect(retry).top, greaterThan(tester.getRect(call).bottom));
  });
}
