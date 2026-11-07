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
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/cho_store.dart';
import 'package:yoma_triage/services/geo.dart';
import 'package:yoma_triage/services/offline_queue.dart';
import 'package:yoma_triage/models/facility_catalog.dart';

import 'helpers/cho_helper.dart';

class _Api extends ApiClient {
  _Api({this.result, this.error});

  final Map<String, dynamic>? result;
  final Object? error;
  final sent = <Map<String, dynamic>>[];
  String? lookedUp;

  @override
  Future<Map<String, dynamic>> lookupCho(String phone) async {
    lookedUp = phone;
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    sent.add(req.toJson());
    throw ApiException(503, 'offline');
  }
}

const _lookup = {
  'name': 'Abiba',
  'phone': '+233240000700',
  'compound_id': 7,
  'compound_name': 'Savelugu CHPS',
  'latitude': 9.6,
  'longitude': -0.8,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  group('ChoStore', () {
    test('has no default compound before setup', () async {
      expect(await ChoStore().load(), isNull);
    });

    test('saves and restores the identity', () async {
      await ChoStore().save(ChoIdentity.fromJson(_lookup));
      final loaded = await ChoStore().load();
      expect(loaded!.phone, '+233240000700');
      expect(loaded.compoundId, 7);
      expect(loaded.compoundName, 'Savelugu CHPS');
      expect(loaded.latitude, 9.6);
    });

    test('corrupt saved data means not set up', () async {
      SharedPreferences.setMockInitialValues({ChoStore.prefsKey: 'not json'});
      expect(await ChoStore().load(), isNull);
    });
  });

  group('first run', () {
    testWidgets('an unregistered phone opens setup, not Home', (tester) async {
      await tester.pumpWidget(const YomaApp());
      await tester.pumpAndSettle();
      expect(find.byType(SetupScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('a phone already set up opens Home', (tester) async {
      SharedPreferences.setMockInitialValues(registeredChoPrefs());
      await tester.pumpWidget(const YomaApp());
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(SetupScreen), findsNothing);
    });
  });

  group('SetupScreen', () {
    Future<ChoIdentity?> submit(WidgetTester tester, ApiClient api, String phone) async {
      ChoIdentity? completed;
      await tester.pumpWidget(
        MaterialApp(
          home: SetupScreen(api: api, onComplete: (i) => completed = i),
        ),
      );
      await tester.enterText(find.byKey(const Key('setup_phone')), phone);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      return completed;
    }

    testWidgets('a registered CHO is stored with the compound from the server',
        (tester) async {
      final api = _Api(result: _lookup);
      final completed = await submit(tester, api, '0240000700');

      expect(api.lookedUp, '0240000700');
      expect(completed!.compoundId, 7);
      expect((await ChoStore().load())!.compoundId, 7);
    });

    testWidgets('an unregistered phone shows the server reason and stores nothing',
        (tester) async {
      final api = _Api(
        error: ApiException(404, '{"detail":"This phone number is not registered as a CHO.","code":"CHO_NOT_REGISTERED"}'),
      );
      final completed = await submit(tester, api, '0240000999');

      expect(completed, isNull);
      expect(find.textContaining('not registered as a CHO'), findsOneWidget);
      expect(await ChoStore().load(), isNull);
    });

    testWidgets('an inactive CHO shows the server reason', (tester) async {
      final api = _Api(error: ApiException(403, '{"detail":"This CHO is no longer active.","code":"CHO_NOT_ACTIVE"}'));
      expect(await submit(tester, api, '0240000700'), isNull);
      expect(find.textContaining('no longer active'), findsOneWidget);
    });

    testWidgets('a captive portal refusal is not shown as a verdict on the CHO',
        (tester) async {
      final api = _Api(error: ApiException(403, '<html>Log in to Wi-Fi</html>'));
      expect(await submit(tester, api, '0240000700'), isNull);
      expect(find.textContaining('you may need to log in'), findsOneWidget);
      expect(find.textContaining('<html>'), findsNothing);
    });

    testWidgets('no network says so and points to a direct call', (tester) async {
      final api = _Api(error: const SocketException('no route'));
      expect(await submit(tester, api, '0240000700'), isNull);
      expect(find.textContaining('No connection'), findsOneWidget);
      expect(find.textContaining('call the driver'), findsOneWidget);
    });

    testWidgets('a server fault is not shown as the CHO being refused', (tester) async {
      final api = _Api(error: ApiException(500, 'boom'));
      expect(await submit(tester, api, '0240000700'), isNull);
      expect(find.textContaining('server is having a problem'), findsOneWidget);
    });

    testWidgets('an empty number is asked for again without calling the server',
        (tester) async {
      final api = _Api(result: _lookup);
      await submit(tester, api, '   ');
      expect(api.lookedUp, isNull);
      expect(find.text('Enter your phone number'), findsOneWidget);
    });

    testWidgets('has no compound picker', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SetupScreen(api: _Api(), onComplete: (_) {})),
      );
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(find.textContaining('Tamale'), findsNothing);
    });
  });

  group('referrals', () {
    late Directory dbDir;
    late OfflineQueue queue;

    setUp(() {
      dbDir = Directory.systemTemp.createTempSync('yoma_cho');
      addTearDown(() => dbDir.deleteSync(recursive: true));
      queue = OfflineQueue(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePathOverride: '${dbDir.path}/outbox.db',
      );
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

    Future<void> chooseTypeAndFacility(WidgetTester tester) async {
      await tester.tap(find.text('Emergency type'));
      await pumpUntil(tester, find.text('Postpartum hemorrhage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Postpartum hemorrhage').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_location_alt));
      await pumpUntil(tester, find.text('Choose receiving facility'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
    }

    testWidgets('a referral carries the CHO phone and their compound, not #1',
        (tester) async {
      SharedPreferences.setMockInitialValues(
        registeredChoPrefs(compoundId: 7, compoundName: 'Savelugu CHPS'),
      );
      final api = _Api();
      await tester.pumpWidget(
        MaterialApp(home: ReferralScreen(queue: queue, api: api)),
      );
      await chooseTypeAndFacility(tester);

      await tester.tap(find.byKey(const Key('referral_skip_vitals')));
      for (var i = 0; i < 200 && api.sent.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }

      expect(api.sent.single['chps_compound_id'], 7);
      expect(api.sent.single['cho_phone'], testChoPhone);
      expect(find.text('Tamale South CHPS'), findsNothing);
    });

    testWidgets('a phone that is not set up cannot send, and says so', (tester) async {
      final api = _Api();
      await tester.pumpWidget(
        MaterialApp(home: ReferralScreen(queue: queue, api: api)),
      );
      await chooseTypeAndFacility(tester);

      await tester.tap(find.byKey(const Key('referral_skip_vitals')));
      await pumpUntil(tester, find.byKey(const Key('referral_skip_error')));

      expect(api.sent, isEmpty);
      expect(find.textContaining('not set up as a CHO'), findsOneWidget);
      expect(find.text('This phone is not set up'), findsOneWidget);
    });

    test('a queued referral keeps its CHO phone when flushed', () async {
      final api = _Api();
      await queue.enqueue(
        ReferralRequest(
          clientRequestId: 'a',
          chpsCompoundId: 7,
          facilityId: 1,
          patientHash: 'h',
          choPhone: testChoPhone,
          emergencyType: 'pph',
          vitals: const {},
        ),
      );
      await queue.flush(api);
      expect(api.sent.single['cho_phone'], testChoPhone);
    });
  });

  group('facility list without a known location', () {
    test('lists every maternity facility by name, distance unknown', () {
      const facilities = [
        CatalogFacility(
          id: 2, name: 'Zebra', latitude: null, longitude: null,
          district: 'D', hasMaternity: true, hasIcu: false, type: 't',
        ),
        CatalogFacility(
          id: 1, name: 'Alpha', latitude: null, longitude: null,
          district: 'D', hasMaternity: true, hasIcu: false, type: 't',
        ),
      ];
      final listed = listByName(facilities: facilities);
      expect(listed.map((r) => r.name), ['Alpha', 'Zebra']);
      expect(listed.first.distanceKm.isNaN, isTrue);
    });
  });
}
