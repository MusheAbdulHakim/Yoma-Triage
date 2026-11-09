import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yoma_triage/models/referral.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/offline_queue.dart';
import 'helpers/cho_helper.dart';

/// Records what would be sent, then fails so the test ends on the queued screen
/// rather than on the live-polling dispatch screen.
class _RecordingApi extends ApiClient {
  final sent = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    sent.add(req.toJson());
    throw ApiException(503, 'offline');
  }
}

const _skip = Key('referral_skip_vitals');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late _RecordingApi api;
  late OfflineQueue queue;
  late Directory dbDir;

  setUp(() {
    // A load left unfinished by an earlier test would otherwise stay cached.
    rootBundle.clear();
    dbDir = Directory.systemTemp.createTempSync('yoma_skip');
    addTearDown(() => dbDir.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues(registeredChoPrefs());
    api = _RecordingApi();
    queue = OfflineQueue(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: '${dbDir.path}/outbox.db',
    );
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ReferralScreen(queue: queue, api: api)),
    );
    await tester.pump();
  }

  /// Real I/O (catalog asset, database) only advances between these real waits.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for $finder');
  }

  Future<void> chooseType(WidgetTester tester) async {
    await tester.tap(find.text('Emergency type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heavy bleeding').last);
    await tester.pumpAndSettle();
  }

  Future<void> chooseFacility(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('referral_send_to')));
    await pumpUntil(tester, find.text('Choose receiving facility'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('(confirmed)'), findsOneWidget);
  }

  Future<void> tapSkipAndWait(WidgetTester tester) async {
    await tester.tap(find.byKey(_skip));
    await pumpUntil(tester, find.byType(QueuedReferralScreen));
    await tester.pumpAndSettle();
  }

  testWidgets('the button is on screen without scrolling, on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);

    expect(find.byKey(_skip).hitTestable(), findsOneWidget);
    expect(find.text('Emergency: skip vitals'), findsOneWidget);
  });

  testWidgets('tapping the facility before the catalog loads still opens it',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ReferralScreen(queue: queue, api: api)),
    );
    // No wait: tap on the first frame, as a CHO on a slow phone might.
    await tester.tap(find.byKey(const Key('referral_send_to')));
    await pumpUntil(tester, find.text('Choose receiving facility'));
  });

  testWidgets('skip without a type is stopped and says why', (tester) async {
    await open(tester);
    await chooseFacility(tester);

    await tester.tap(find.byKey(_skip));
    await tester.pump();

    expect(find.text('Choose the emergency type first'), findsOneWidget);
    expect(api.sent, isEmpty);
  });

  testWidgets('skip without a facility is stopped and says why', (tester) async {
    await open(tester);
    await chooseType(tester);

    await tester.tap(find.byKey(_skip));
    await pumpUntil(tester, find.byKey(const Key('referral_skip_error')));

    expect(
      find.text('Tap above to choose the receiving facility first'),
      findsOneWidget,
    );
    expect(api.sent, isEmpty);
  });

  testWidgets('type and facility alone send it: no name, no vitals',
      (tester) async {
    await open(tester);
    await chooseType(tester);
    await chooseFacility(tester);

    await tapSkipAndWait(tester);

    expect(api.sent, hasLength(1));
    expect(api.sent.single['vitals_taken'], isFalse);
    expect(api.sent.single['emergency_type'], 'pph');
    expect(api.sent.single['vitals'], isEmpty);
    expect(api.sent.single.containsKey('patient_name'), isFalse);
    expect(find.byType(QueuedReferralScreen), findsOneWidget);
  });

  testWidgets('no network: the referral is kept and is honest about drivers',
      (tester) async {
    await open(tester);
    await chooseType(tester);
    await chooseFacility(tester);

    await tapSkipAndWait(tester);

    expect(find.textContaining('Drivers have not been notified'), findsOneWidget);
    final pending = await tester.runAsync(queue.pending);
    expect(pending, hasLength(1));
    expect(pending!.single.payload['vitals_taken'], isFalse);
  });

  testWidgets('the normal path still asks for each answer', (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);

    // No type yet: Send can't be tapped, so nothing can go out.
    final send = find.byKey(const Key('referral_send'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.tap(send, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(api.sent, isEmpty);

    // With a type, the rest of the form is still checked on tap.
    await tester.tap(find.byKey(const Key('referral_type_pph')));
    await tester.pump();
    await tester.tap(send);
    await pumpUntil(tester, find.textContaining('Choose receiving facility'));
    expect(api.sent, isEmpty);

    // Facility confirmed, still no vitals: it asks for them (or skip vitals).
    await chooseFacility(tester);
    await tester.tap(send);
    await pumpUntil(tester, find.textContaining('Record vitals first'));
    expect(api.sent, isEmpty);
  });

  test('a queued skip-vitals referral keeps its flag when flushed', () async {
    final retry = _RecordingApi();
    await queue.enqueue(
      ReferralRequest(
        clientRequestId: 'skip-1',
        chpsCompoundId: 1,
        facilityId: 1,
        patientHash: 'h',
        choPhone: '+233240000100',
        emergencyType: 'pph',
        vitals: const {},
        vitalsTaken: false,
      ),
    );

    await queue.flush(retry);

    expect(retry.sent.single['vitals_taken'], isFalse);
  });

  test('an ordinary referral does not send the flag', () {
    final json = ReferralRequest(
      clientRequestId: 'x',
      chpsCompoundId: 1,
      facilityId: 1,
      patientHash: 'h',
      choPhone: '+233240000100',
      emergencyType: 'pph',
      vitals: const {'systolic_bp': 120},
    ).toJson();
    expect(json.containsKey('vitals_taken'), isFalse);
  });
}
