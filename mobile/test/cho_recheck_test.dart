import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yoma_triage/main.dart';
import 'package:yoma_triage/models/referral.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/screens/setup_screen.dart';
import 'package:yoma_triage/screens/unsent_referrals_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/cho_store.dart';
import 'package:yoma_triage/services/contacts_store.dart';
import 'package:yoma_triage/services/offline_queue.dart';
import 'package:yoma_triage/services/queue_sync_service.dart';

import 'helpers/cho_helper.dart';

const _driver = '+233240000001';

ApiException _refusal(int status, String code) =>
    ApiException(status, jsonEncode({'detail': 'refused', 'code': code}));

class _Server extends ApiClient {
  _Server({this.lookupResult, this.lookupError});

  Map<String, dynamic>? lookupResult;
  Object? lookupError;
  int lookups = 0;
  int contactCalls = 0;

  @override
  Future<Map<String, dynamic>> lookupCho(String phone) async {
    lookups++;
    if (lookupError != null) throw lookupError!;
    return lookupResult ?? _active();
  }

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    throw _refusal(403, 'CHO_NOT_ACTIVE');
  }

  @override
  Future<Map<String, dynamic>> getCompoundContacts(int compoundId) async {
    contactCalls++;
    throw const SocketException('not under test');
  }

  @override
  Future<Map<String, dynamic>> getReferralGraph({
    String region = 'northern',
    String? district,
  }) async =>
      throw const SocketException('not under test');
}

Map<String, dynamic> _active({
  int compoundId = 1,
  String compoundName = 'Tamale South CHPS',
  String name = 'Abiba',
}) =>
    {
      'name': name,
      'phone': testChoPhone,
      'compound_id': compoundId,
      'compound_name': compoundName,
    };

ReferralRequest _sample(String id) => ReferralRequest(
      clientRequestId: id,
      chpsCompoundId: 1,
      facilityId: 1,
      patientHash: 'h',
      choPhone: testChoPhone,
      emergencyType: 'pph',
      vitals: const {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late OfflineQueue queue;
  late Directory dbDir;

  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues(registeredChoPrefs());
    dbDir = Directory.systemTemp.createTempSync('yoma_recheck');
    addTearDown(() => dbDir.deleteSync(recursive: true));
    queue = OfflineQueue(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: '${dbDir.path}/outbox.db',
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
  }

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('ChoStore.recheck', () {
    test('still active at the same compound: stays, and picks up changes', () async {
      final removed = await ChoStore().recheck(
        _Server(lookupResult: _active(compoundName: 'New Name', name: 'Abiba K')),
      );

      expect(removed, isFalse);
      final identity = await ChoStore().load();
      expect(identity!.compoundName, 'New Name');
      expect(identity.name, 'Abiba K');
      expect(await ChoStore().loadNotice(), isNull);
    });

    test('deactivated: back to setup, and says why', () async {
      final before = ChoStore.removals.value;
      final removed = await ChoStore().recheck(
        _Server(lookupError: _refusal(403, 'CHO_NOT_ACTIVE')),
      );

      expect(removed, isTrue);
      expect(await ChoStore().load(), isNull);
      expect(await ChoStore().loadNotice(), contains('no longer active'));
      expect(ChoStore.removals.value, before + 1);
    });

    test('no longer registered: back to setup, and says why', () async {
      await ChoStore().recheck(
        _Server(lookupError: _refusal(404, 'CHO_NOT_REGISTERED')),
      );

      expect(await ChoStore().load(), isNull);
      expect(await ChoStore().loadNotice(), contains('no longer registered'));
    });

    test('moved: back to setup, and names the new compound', () async {
      final removed = await ChoStore().recheck(
        _Server(lookupResult: _active(compoundId: 2, compoundName: 'Navrongo CHPS')),
      );

      expect(removed, isTrue);
      expect(await ChoStore().load(), isNull);
      expect(await ChoStore().loadNotice(), contains('Navrongo CHPS'));
    });

    for (final (name, error) in <(String, Object)>[
      ('no network', const SocketException('no signal')),
      ('a server error', ApiException(500, 'oops')),
      ('a captive portal 403', ApiException(403, '<html>Log in to Wi-Fi</html>')),
      ('a captive portal 401', ApiException(401, '<html>Log in</html>')),
      ('a proxy 404', ApiException(404, '{"detail":"Not Found"}')),
      ('an unknown code', ApiException(403, '{"detail":"x","code":"SOMETHING_ELSE"}')),
    ]) {
      test('$name never logs the CHO out', () async {
        final removed = await ChoStore().recheck(_Server(lookupError: error));

        expect(removed, isFalse);
        expect(await ChoStore().load(), isNotNull);
        expect(await ChoStore().loadNotice(), isNull);
      });
    }

    test('a 200 that is not our answer never logs the CHO out', () async {
      final removed = await ChoStore().recheck(
        _Server(lookupResult: {'welcome': 'to the Wi-Fi'}),
      );

      expect(removed, isFalse);
      expect(await ChoStore().load(), isNotNull);
    });

    test('a phone that was never set up asks nothing', () async {
      SharedPreferences.setMockInitialValues({});
      final server = _Server();
      expect(await ChoStore().recheck(server), isFalse);
      expect(server.lookups, 0);
    });

    test('setting up again clears the notice', () async {
      await ChoStore().recheck(_Server(lookupError: _refusal(403, 'CHO_NOT_ACTIVE')));
      await ChoStore().save(ChoIdentity.fromJson(_active()));
      expect(await ChoStore().loadNotice(), isNull);
    });
  });

  group('re-checked on every sync', () {
    test('when the sync service starts', () async {
      final server = _Server();
      final service = QueueSyncService(queue: queue, api: server);
      addTearDown(service.dispose);
      service.start();
      for (var i = 0; i < 200 && server.lookups == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(server.lookups, 1);
    });

    testWidgets('when Home opens', (tester) async {
      final server = _Server();
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(api: server, queue: queue, acousticEnabled: false)),
      );
      await settle(tester);
      expect(server.lookups, 1);
    });

    test('contacts are not fetched for a compound the CHO has left', () async {
      final server = _Server(lookupError: _refusal(403, 'CHO_NOT_ACTIVE'));
      final service = QueueSyncService(queue: queue, api: server);
      addTearDown(service.dispose);
      service.start();
      for (var i = 0; i < 200 && server.lookups == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.lookups, 1);
      expect(server.contactCalls, 0);
    });
  });

  group('back at setup', () {
    Map<String, Object> savedContacts() => {
          ContactsStore.prefsKey: jsonEncode({
            'compound_id': 1,
            'drivers': [
              {'name': 'Ibrahim', 'phone': _driver, 'is_motor_king': true},
            ],
            'facilities': [],
          }),
          ContactsStore.updatedAtPrefsKey: DateTime.utc(2026, 11, 5).toIso8601String(),
        };

    testWidgets('explains why, and the unsent referrals are visible', (tester) async {
      useTallScreen(tester);
      SharedPreferences.setMockInitialValues({
        ChoStore.noticePrefsKey: 'This phone number is no longer active as a CHO.',
        ...savedContacts(),
      });
      await tester.runAsync(() => queue.enqueue(_sample('a')));
      await tester.pumpWidget(
        MaterialApp(
          home: SetupScreen(onComplete: (_) {}, api: _Server(), queue: queue),
        ),
      );
      await settle(tester);

      expect(find.byKey(const Key('setup_notice')), findsOneWidget);
      expect(find.textContaining('no longer active'), findsOneWidget);
      expect(find.text('1 referral has not reached a driver'), findsOneWidget);
    });

    testWidgets('unsent list shows pending and refused, with working Call and SMS',
        (tester) async {
      useTallScreen(tester);
      SharedPreferences.setMockInitialValues({
        ChoStore.noticePrefsKey: 'Moved.',
        ...savedContacts(),
      });
      final launched = <Uri>[];
      await tester.runAsync(() async {
        await queue.enqueue(_sample('pending-one'));
        await queue.enqueue(_sample('refused-one'));
        await queue.markFailed('refused-one', 'This CHO is no longer active.');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: UnsentReferralsScreen(
            queue: queue,
            api: _Server(),
            launcher: (uri) async {
              launched.add(uri);
              return true;
            },
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const Key('unsent_pending-one')), findsOneWidget);
      expect(find.byKey(const Key('unsent_refused-one')), findsOneWidget);
      expect(find.textContaining('no longer active'), findsOneWidget);
      await tester.tap(find.byKey(const Key('call_$_driver')));
      await tester.pump();
      expect(launched.single.toString(), 'tel:$_driver');
      await settle(tester);
      await tester.runAsync(() async {
        final pending = await queue.pending();
        expect(pending.single.manualContactMade, isTrue);
      });
    });

    testWidgets('a clean first run shows neither', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: SetupScreen(onComplete: (_) {}, api: _Server(), queue: queue),
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('setup_notice')), findsNothing);
      expect(find.byKey(const Key('setup_unsent')), findsNothing);
    });

    testWidgets('the app leaves whatever screen is open and returns to setup',
        (tester) async {
      await tester.pumpWidget(const YomaApp());
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.tap(find.text('Emergency referral'));
      await settle(tester);
      expect(find.byType(ReferralScreen), findsOneWidget);

      await tester.runAsync(
        () => ChoStore().recheck(_Server(lookupError: _refusal(403, 'CHO_NOT_ACTIVE'))),
      );
      await settle(tester);

      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ReferralScreen), findsNothing);
      expect(find.byType(SetupScreen), findsOneWidget);
      expect(find.byKey(const Key('setup_notice')), findsOneWidget);
    });
  });
}
