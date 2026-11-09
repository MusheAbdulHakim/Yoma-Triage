import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yoma_triage/models/referral.dart';
import 'package:yoma_triage/screens/dispatch_status_screen.dart';
import 'package:yoma_triage/screens/failed_referrals_screen.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';
import 'package:yoma_triage/screens/setup_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/contacts_store.dart';
import 'package:yoma_triage/services/offline_queue.dart';
import 'package:yoma_triage/services/queue_sync_service.dart';
import 'package:yoma_triage/widgets/manual_contacts_panel.dart';

import 'helpers/cho_helper.dart';

const _driver = '+233240000001';
const _volunteer = '+233240000003';
const _chosenHospital = '+233240000200';
const _otherHospital = '+233240000201';

const _serverContacts = {
  'compound_id': 1,
  'drivers': [
    {'name': 'Ibrahim', 'phone': _driver, 'is_motor_king': true},
    {'name': 'Abdul', 'phone': _volunteer, 'is_motor_king': false},
  ],
  'facilities': [
    {'id': 1, 'name': 'Tamale Teaching Hospital', 'phone': _chosenHospital},
    {'id': 2, 'name': 'Other Hospital', 'phone': _otherHospital},
  ],
};

/// Fails every request, as a phone with no signal would.
class _OfflineApi extends ApiClient {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getCompoundContacts(int compoundId) async {
    calls++;
    throw const SocketException('no signal');
  }

  @override
  Future<Map<String, dynamic>> getDispatch(int id) async {
    calls++;
    throw const SocketException('no signal');
  }

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    calls++;
    throw const SocketException('no signal');
  }
}

class _ContactsApi extends ApiClient {
  _ContactsApi(this.body);

  final Map<String, dynamic> body;

  @override
  Future<Map<String, dynamic>> getCompoundContacts(int compoundId) async => body;
}

class _FailedDispatchApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> getDispatch(int id) async => {
        'id': id,
        'status': 'FAILED',
        'current_tier': 3,
        'facility_id': 1,
      };
}

class _RefusingApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    throw ApiException(404, '{"detail":"Facility not found","code":"FACILITY_NOT_FOUND"}');
  }
}

Map<String, Object> _savedPrefs() => {
      ...registeredChoPrefs(compoundName: 'Savelugu CHPS'),
      ContactsStore.prefsKey: jsonEncode(_serverContacts),
      ContactsStore.updatedAtPrefsKey: DateTime.utc(2026, 11, 5, 14, 3).toIso8601String(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  _refreshTriggerTests();

  late List<Uri> launched;
  Future<bool> recordLaunch(Uri uri) async {
    launched.add(uri);
    return true;
  }

  setUp(() {
    launched = [];
    rootBundle.clear();
    SharedPreferences.setMockInitialValues(_savedPrefs());
  });

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

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpPanel(WidgetTester tester, {Set<int> facilityIds = const {1}}) async {
    useTallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ManualContactsPanel(facilityIds: facilityIds, launcher: recordLaunch),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ContactsStore', () {
    test('saves what the server returned and when', () async {
      SharedPreferences.setMockInitialValues(registeredChoPrefs());
      final saved = await ContactsStore().refresh(_ContactsApi(_serverContacts), 1);

      expect(saved, isTrue);
      final contacts = await ContactsStore().load();
      expect(contacts!.drivers.map((d) => d.phone), [_driver, _volunteer]);
      expect(contacts.drivers.first.isMotorKing, isTrue);
      expect(contacts.drivers.last.isMotorKing, isFalse);
      expect(contacts.facilities.first.phone, _chosenHospital);
      expect(
        DateTime.now().toUtc().difference(contacts.updatedAt).inMinutes,
        lessThan(1),
      );
    });

    test('offline refresh keeps the saved list and its date', () async {
      final saved = await ContactsStore().refresh(_OfflineApi(), 1);

      expect(saved, isFalse);
      final contacts = await ContactsStore().load();
      expect(contacts!.drivers, hasLength(2));
      expect(contacts.updatedAt, DateTime.utc(2026, 11, 5, 14, 3));
    });

    test('a malformed reply cannot replace a good list', () async {
      final saved = await ContactsStore().refresh(
        _ContactsApi(const {'drivers': 'oops', 'facilities': []}),
        1,
      );

      expect(saved, isFalse);
      expect((await ContactsStore().load())!.drivers, hasLength(2));
    });

    test('refreshForThisPhone does nothing before setup', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _OfflineApi();
      expect(await ContactsStore().refreshForThisPhone(api), isFalse);
      expect(api.calls, 0);
    });

    test('nothing saved loads as null', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ContactsStore().load(), isNull);
    });
  });

  group('ManualContactsPanel', () {
    testWidgets('shows Call and SMS for each driver and the chosen facility only',
        (tester) async {
      await pumpPanel(tester);

      for (final phone in [_driver, _volunteer, _chosenHospital]) {
        expect(find.byKey(Key('call_$phone')), findsOneWidget, reason: phone);
        expect(find.byKey(Key('sms_$phone')), findsOneWidget, reason: phone);
      }
      expect(find.byKey(const Key('call_$_otherHospital')), findsNothing);
      expect(find.textContaining('Motor-King'), findsOneWidget);
      expect(find.textContaining('Other vehicle'), findsOneWidget);
    });

    testWidgets('Call opens the dialler with the number', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byKey(const Key('call_$_driver')));
      await tester.pump();
      expect(launched.single.toString(), 'tel:$_driver');
    });

    testWidgets('SMS opens messaging with a short prefilled message and no patient name',
        (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byKey(const Key('sms_$_driver')));
      await tester.pump();

      final uri = launched.single;
      expect(uri.scheme, 'sms');
      expect(uri.path, _driver);
      final body = uri.queryParameters['body']!;
      expect(body, contains('Savelugu CHPS'));
      expect(body.length, lessThanOrEqualTo(160));
      expect(uri.toString(), contains('%20'), reason: 'spaces must not become +');
      expect(uri.toString().toLowerCase(), isNot(contains('patient')));
    });

    testWidgets('facility SMS has its own message and no patient name', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byKey(const Key('sms_$_chosenHospital')));
      await tester.pump();

      final body = launched.single.queryParameters['body']!;
      expect(body, contains('referral coming from Savelugu CHPS'));
      expect(body.length, lessThanOrEqualTo(160));
      expect(body.toLowerCase(), isNot(contains('patient')));
    });

    testWidgets('shows when the list was last updated', (tester) async {
      await pumpPanel(tester);
      final text = tester.widget<Text>(find.byKey(const Key('contacts_updated'))).data!;
      // A friendly date (the saved time is in the past), never a raw ISO timestamp.
      expect(text, startsWith('Contacts last updated: 5 Nov, '));
      expect(text, isNot(contains('2026-')));
    });

    testWidgets('says so when nothing has been saved yet', (tester) async {
      SharedPreferences.setMockInitialValues(registeredChoPrefs());
      await pumpPanel(tester);
      expect(find.byKey(const Key('contacts_none_saved')), findsOneWidget);
    });

    testWidgets('if the phone app cannot open, shows the number to dial', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ManualContactsPanel(
                facilityIds: const {1},
                launcher: (_) async => false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call_$_driver')));
      await tester.pump();
      expect(find.text('Could not open the phone app. Dial $_driver by hand.'), findsOneWidget);
    });

    testWidgets('a launcher that throws is handled the same way', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ManualContactsPanel(
                facilityIds: const {1},
                launcher: (_) async => throw StateError('no dialler'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call_$_driver')));
      await tester.pump();
      expect(find.textContaining('Dial $_driver by hand'), findsOneWidget);
    });
  });

  group('offline: where the CHO sees it', () {
    late OfflineQueue queue;
    late Directory dbDir;

    setUp(() {
      dbDir = Directory.systemTemp.createTempSync('yoma_fallback');
      addTearDown(() => dbDir.deleteSync(recursive: true));
      queue = OfflineQueue(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePathOverride: '${dbDir.path}/outbox.db',
      );
    });

    ReferralRequest sample(String id) => ReferralRequest(
          clientRequestId: id,
          chpsCompoundId: 1,
          facilityId: 1,
          patientHash: 'h',
          choPhone: testChoPhone,
          emergencyType: 'pph',
          vitals: const {},
        );

    testWidgets('queued referral: buttons work with no network at all', (tester) async {
      useTallScreen(tester);
      final api = _OfflineApi();
      await tester.pumpWidget(
        MaterialApp(
          home: QueuedReferralScreen(
            clientRequestId: 'a',
            queue: queue,
            api: api,
            facilityId: 1,
            launcher: recordLaunch,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.calls, 0, reason: 'the panel must not need the network');
      await tester.tap(find.byKey(const Key('call_$_chosenHospital')));
      await tester.tap(find.byKey(const Key('call_$_driver')));
      await tester.pump();

      expect(launched.map((u) => u.toString()), ['tel:$_chosenHospital', 'tel:$_driver']);
      expect(find.byKey(const Key('contacts_updated')), findsOneWidget);
      expect(find.textContaining('Drivers have not been notified'), findsOneWidget);
    });

    testWidgets('queued referral: a failed retry leaves the buttons working', (tester) async {
      useTallScreen(tester);
      await tester.runAsync(() => queue.enqueue(sample('a')));
      await tester.pumpWidget(
        MaterialApp(
          home: QueuedReferralScreen(
            clientRequestId: 'a',
            queue: queue,
            api: _OfflineApi(),
            facilityId: 1,
            launcher: recordLaunch,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry sync'));
      await pumpUntil(tester, find.textContaining('Still waiting for coverage'));
      await pumpUntil(tester, find.byKey(const Key('sms_$_driver')));

      await tester.tap(find.byKey(const Key('sms_$_driver')));
      await tester.pump();
      expect(launched.single.scheme, 'sms');
    });

    testWidgets('failed referral: shows the facility that referral chose', (tester) async {
      useTallScreen(tester);
      await tester.runAsync(() async {
        await queue.enqueue(sample('a'));
        await queue.flush(_RefusingApi());
      });
      await tester.pumpWidget(
        MaterialApp(
          home: FailedReferralsScreen(queue: queue, launcher: recordLaunch),
        ),
      );
      await pumpUntil(tester, find.byKey(const Key('call_$_chosenHospital')));

      expect(find.byKey(const Key('call_$_otherHospital')), findsNothing);
      expect(find.byKey(const Key('call_$_driver')), findsOneWidget);
      // No raw request id outside test builds.
      expect(find.textContaining('Request:'), findsNothing);
      await tester.tap(find.byKey(const Key('call_$_driver')));
      await tester.pump();
      expect(launched.single.toString(), 'tel:$_driver');
    });

    testWidgets('dispatch reaches FAILED: buttons appear', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: DispatchStatusScreen(
            dispatchId: 9,
            clientRequestId: 'a',
            api: _FailedDispatchApi(),
            queue: queue,
            launcher: recordLaunch,
          ),
        ),
      );
      await pumpUntil(tester, find.byKey(const Key('call_$_chosenHospital')));

      expect(find.byKey(const Key('dispatch_status_FAILED')), findsOneWidget);
      await tester.tap(find.byKey(const Key('call_$_driver')));
      await tester.pump();
      expect(launched.single.toString(), 'tel:$_driver');
    });
  });
}

class _CountingApi extends ApiClient {
  int contactCalls = 0;

  @override
  Future<Map<String, dynamic>> getCompoundContacts(int compoundId) async {
    contactCalls++;
    return _serverContacts;
  }

  @override
  Future<Map<String, dynamic>> lookupCho(String phone) async => const {
        'name': 'Abiba',
        'phone': testChoPhone,
        'compound_id': 1,
        'compound_name': 'Savelugu CHPS',
      };

  @override
  Future<Map<String, dynamic>> getReferralGraph({
    String region = 'northern',
    String? district,
  }) async =>
      throw const SocketException('catalog not under test');
}

class _FakeConnectivity implements Connectivity {
  final controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The sync does real database work first, so a fixed delay would be flaky.
Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void _refreshTriggerTests() {
  group('when the saved list is refreshed', () {
    late Directory dbDir;

    OfflineQueue queueInTempDir() {
      dbDir = Directory.systemTemp.createTempSync('yoma_sync');
      addTearDown(() => dbDir.deleteSync(recursive: true));
      return OfflineQueue(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePathOverride: '${dbDir.path}/outbox.db',
      );
    }

    testWidgets('after setup', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _CountingApi();
      await tester.pumpWidget(
        MaterialApp(home: SetupScreen(api: api, onComplete: (_) {})),
      );
      await tester.enterText(find.byKey(const Key('setup_phone')), '0240000100');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(api.contactCalls, 1);
      expect((await ContactsStore().load())!.drivers, hasLength(2));
    });

    testWidgets('a failed setup refreshes nothing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _OfflineApi();
      await tester.pumpWidget(
        MaterialApp(home: SetupScreen(api: api, onComplete: (_) {})),
      );
      await tester.enterText(find.byKey(const Key('setup_phone')), '0240000100');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(api.calls, 0);
    });

    testWidgets('when Home opens', (tester) async {
      SharedPreferences.setMockInitialValues(registeredChoPrefs());
      final api = _CountingApi();
      await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api)));
      await tester.pumpAndSettle();

      expect(api.contactCalls, 1);
      expect(await ContactsStore().load(), isNotNull);
    });

    test('when the sync service starts', () async {
      SharedPreferences.setMockInitialValues(registeredChoPrefs());
      final api = _CountingApi();
      final service = QueueSyncService(
        queue: queueInTempDir(),
        api: api,
        connectivity: _FakeConnectivity(),
      );
      addTearDown(service.dispose);

      service.start();
      await _waitFor(() => api.contactCalls > 0);

      expect(api.contactCalls, 1);
    });

    test('when the connection comes back, but not when it drops', () async {
      SharedPreferences.setMockInitialValues(registeredChoPrefs());
      final api = _CountingApi();
      final connectivity = _FakeConnectivity();
      final service = QueueSyncService(
        queue: queueInTempDir(),
        api: api,
        connectivity: connectivity,
      );
      addTearDown(service.dispose);
      service.start();
      await _waitFor(() => api.contactCalls > 0);
      api.contactCalls = 0;

      connectivity.controller.add([ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.contactCalls, 0);

      connectivity.controller.add([ConnectivityResult.mobile]);
      await _waitFor(() => api.contactCalls > 0);
      expect(api.contactCalls, 1);
    });
  });
}
