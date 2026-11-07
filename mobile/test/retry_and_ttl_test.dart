import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yoma_triage/models/referral.dart';
import 'package:yoma_triage/parameters.dart';
import 'package:yoma_triage/screens/failed_referrals_screen.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';
import 'package:yoma_triage/screens/setup_screen.dart';
import 'package:yoma_triage/screens/unsent_referrals_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/offline_queue.dart';
import 'package:yoma_triage/services/queue_sync_service.dart';

import 'helpers/cho_helper.dart';

const _ours = '{"detail":"Facility not found","code":"FACILITY_NOT_FOUND"}';
const _portal = '<html>Log in to Wi-Fi</html>';

ReferralRequest _sample(String id) => ReferralRequest(
      clientRequestId: id,
      chpsCompoundId: 1,
      facilityId: 1,
      patientHash: 'h',
      choPhone: testChoPhone,
      emergencyType: 'pph',
      vitals: const {},
    );

class _Server extends ApiClient {
  _Server({this.error, this.staleReply = false});

  Object? error;
  bool staleReply;
  int sends = 0;

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    sends++;
    if (error != null) throw error!;
    return {
      'referral': {'id': 1, 'status': staleReply ? 'AWAITING_CONFIRMATION' : 'CONFIRMED'},
      'dispatch': staleReply ? null : {'id': 1},
    };
  }

  @override
  Future<Map<String, dynamic>> lookupCho(String phone) async =>
      throw const SocketException('not under test');

  @override
  Future<Map<String, dynamic>> getCompoundContacts(int compoundId) async =>
      throw const SocketException('not under test');

  @override
  Future<Map<String, dynamic>> getReferralGraph({
    String region = 'northern',
    String? district,
  }) async =>
      throw const SocketException('not under test');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late OfflineQueue queue;
  late Directory dbDir;
  final created = DateTime.now();
  DateTime hoursIn(num hours) =>
      created.add(Duration(minutes: (hours * 60).round()));
  const ttl = Parameters.localRecordTtlHours;
  const warning = Parameters.localRecordWarningHours;

  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues(registeredChoPrefs());
    dbDir = Directory.systemTemp.createTempSync('yoma_ttl');
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

  group('flush', () {
    test('a captive portal 403 keeps the referral and raises a warning', () async {
      await queue.enqueue(_sample('a'));
      await queue.flush(_Server(error: ApiException(403, _portal)));

      expect((await queue.pending()).single.clientRequestId, 'a');
      expect(await queue.failed(), isEmpty);
      expect(queue.retryWarning.value, contains('HTTP 403'));
    });

    test('a 401 from our API without a code also keeps it and warns', () async {
      await queue.enqueue(_sample('a'));
      await queue.flush(
        _Server(error: ApiException(401, '{"detail":"Invalid or missing X-API-Key"}')),
      );
      expect(await queue.pending(), hasLength(1));
      expect(queue.retryWarning.value, contains('HTTP 401'));
    });

    test('a refusal with our code fails it, with no warning', () async {
      await queue.enqueue(_sample('a'));
      await queue.flush(_Server(error: ApiException(404, _ours)));

      expect(await queue.pending(), isEmpty);
      expect((await queue.failed()).single.lastError, 'Facility not found');
      expect(queue.retryWarning.value, isNull);
    });

    for (final (name, error) in <(String, Object)>[
      ('a 503', ApiException(503, 'down')),
      ('a 429', ApiException(429, 'slow down')),
      ('no network', const SocketException('no signal')),
    ]) {
      test('$name retries with no warning', () async {
        await queue.enqueue(_sample('a'));
        await queue.flush(_Server(error: error));
        expect(await queue.pending(), hasLength(1));
        expect(queue.retryWarning.value, isNull);
      });
    }

    test('the warning clears once referrals get through', () async {
      await queue.enqueue(_sample('a'));
      final server = _Server(error: ApiException(403, _portal));
      await queue.flush(server);
      expect(queue.retryWarning.value, isNotNull);

      server.error = null;
      await queue.flush(server);

      expect(queue.retryWarning.value, isNull);
      expect(await queue.pending(), isEmpty);
    });

    test('it is retried on the next flush', () async {
      await queue.enqueue(_sample('a'));
      final server = _Server(error: ApiException(403, _portal));
      await queue.flush(server);
      await queue.flush(server);
      expect(server.sends, 2);
    });
  });

  group('the warning is visible', () {
    testWidgets('on Home', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(api: _Server(), queue: queue, acousticEnabled: false)),
      );
      await settle(tester);
      expect(find.byKey(const Key('home_retry_warning')), findsNothing);

      queue.noteRetryWarning(ApiException(403, _portal).retryWarning);
      await tester.pump();
      // Warnings are behind one summary banner on Home.
      await tester.tap(find.byKey(const Key('home_warnings_summary')));
      await tester.pump();

      expect(find.byKey(const Key('home_retry_warning')), findsOneWidget);
      expect(find.textContaining('log in'), findsWidgets);
    });

    testWidgets('on the queued screen after Retry sync', (tester) async {
      useTallScreen(tester);
      await tester.runAsync(() => queue.enqueue(_sample('a')));
      await tester.pumpWidget(
        MaterialApp(
          home: QueuedReferralScreen(
            clientRequestId: 'a',
            queue: queue,
            api: _Server(error: ApiException(403, _portal)),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Retry sync'));
      await settle(tester);

      expect(find.byKey(const Key('queued_retry_warning')), findsOneWidget);
    });
  });

  group('Mark handled', () {
    Future<void> pumpFailed(WidgetTester tester) async {
      useTallScreen(tester);
      await tester.runAsync(() async {
        await queue.enqueue(_sample('a'));
        await queue.enqueue(_sample('b'));
        await queue.flush(_Server(error: ApiException(404, _ours)));
      });
      await tester.pumpWidget(MaterialApp(home: FailedReferralsScreen(queue: queue)));
      await settle(tester);
    }

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('mark_handled_a')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('deletes that record and leaves the others', (tester) async {
      await pumpFailed(tester);
      await openDialog(tester);
      await tester.tap(find.byKey(const Key('mark_handled_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);

      expect(find.byKey(const Key('mark_handled_a')), findsNothing);
      expect(find.byKey(const Key('mark_handled_b')), findsOneWidget);
      expect(queue.failedCount.value, 1);
      await tester.runAsync(() async {
        expect((await queue.failed()).single.clientRequestId, 'b');
      });
    });

    testWidgets('Keep it deletes nothing', (tester) async {
      await pumpFailed(tester);
      await openDialog(tester);
      await tester.tap(find.text('Keep it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);

      expect(find.byKey(const Key('mark_handled_a')), findsOneWidget);
      expect(queue.failedCount.value, 2);
    });

    test('does not touch a referral that is still trying to send', () async {
      await queue.enqueue(_sample('a'));
      await queue.markHandled('a');
      expect(await queue.pending(), hasLength(1));
    });
  });

  group('local record TTL', () {
    test('nothing is warned about or deleted before the warning period', () async {
      await queue.enqueue(_sample('a'));
      final before = hoursIn(ttl - warning - 1);

      expect(await queue.noteExpiryWarning(now: before), 0);
      expect(await queue.purgeExpired(now: before), 0);
      expect(queue.expiringCount.value, 0);
      expect((await queue.pending()).single.expiryWarnedAt, isNull);
    });

    test('a record entering the warning period is counted and stamped', () async {
      await queue.enqueue(_sample('a'));
      final soon = hoursIn(ttl - warning + 1);

      expect(await queue.noteExpiryWarning(now: soon), 1);

      expect(queue.expiringCount.value, 1);
      expect((await queue.pending()).single.expiryWarnedAt, soon);
    });

    test('warned on time: deleted once past the TTL', () async {
      await queue.enqueue(_sample('a'));
      await queue.noteExpiryWarning(now: hoursIn(ttl - warning + 1));

      expect(await queue.purgeExpired(now: hoursIn(ttl - 1)), 0, reason: 'not yet expired');
      expect(await queue.pending(), hasLength(1));

      expect(await queue.purgeExpired(now: hoursIn(ttl + 2)), 1);
      expect(await queue.pending(), isEmpty);
    });

    test('never warned: past the TTL is still not deleted', () async {
      await queue.enqueue(_sample('a'));

      expect(await queue.purgeExpired(now: hoursIn(ttl * 10)), 0);
      expect(await queue.pending(), hasLength(1));
    });

    test('a phone left off for a week warns first, then waits the full period', () async {
      await queue.enqueue(_sample('a'));
      final backOn = hoursIn(ttl * 3);

      await queue.noteExpiryWarning(now: backOn);
      expect(
        await queue.purgeExpired(
          now: backOn.add(const Duration(hours: warning - 1)),
        ),
        0,
      );
      expect(
        await queue.purgeExpired(now: backOn.add(const Duration(hours: warning))),
        1,
      );
    });

    test('a warning from before a longer TTL does not delete early', () async {
      // An update can raise the TTL over a record already warned under the old one.
      await queue.enqueue(_sample('a'));
      await queue.pending();
      // The same connection the queue holds, so it stays open.
      final db = await databaseFactoryFfi.openDatabase('${dbDir.path}/outbox.db');
      final row = (await db.query('referral_outbox')).single;
      final payload = jsonDecode(row['payload_json']! as String) as Map<String, dynamic>;
      payload['local_expiry_warned_at'] = hoursIn(1).toIso8601String();
      await db.update('referral_outbox', {'payload_json': jsonEncode(payload)});

      expect(await queue.purgeExpired(now: hoursIn(1 + warning)), 0);
      expect(await queue.pending(), hasLength(1));
    });

    test('a later warning does not restart the clock', () async {
      await queue.enqueue(_sample('a'));
      final first = hoursIn(ttl - warning + 1);
      await queue.noteExpiryWarning(now: first);
      await queue.noteExpiryWarning(now: hoursIn(ttl));
      expect((await queue.pending()).single.expiryWarnedAt, first);
    });

    test('covers failed and stale records, and updates the counts', () async {
      await queue.enqueue(_sample('refused'));
      await queue.flush(_Server(error: ApiException(404, _ours)));
      await queue.enqueue(_sample('stale'));
      await queue.flush(_Server(staleReply: true));
      expect(queue.failedCount.value, 1);
      expect(queue.needsConfirmationCount.value, 1);

      await queue.noteExpiryWarning(now: hoursIn(ttl - warning + 1));
      expect(queue.expiringCount.value, 2);
      expect(await queue.purgeExpired(now: hoursIn(ttl + 1)), 2);

      expect(queue.failedCount.value, 0);
      expect(queue.needsConfirmationCount.value, 0);
      expect(queue.expiringCount.value, 0);
      expect(await queue.unsent(), isEmpty);
    });

    test('the warning note is never sent to the server', () async {
      await queue.enqueue(_sample('a'));
      await queue.noteExpiryWarning(now: hoursIn(ttl - 1));
      final sent = <String>[];
      await queue.flush(_Recording(sent));
      expect(sent.single, isNot(contains('local_')));
    });

    test('the sync service deletes what has expired', () async {
      await queue.enqueue(_sample('a'));
      final db = await databaseFactoryFfi.openDatabase('${dbDir.path}/outbox.db');
      await db.update('referral_outbox', {
        'created_at':
            DateTime.now().subtract(const Duration(hours: ttl + 1)).toIso8601String(),
      });
      await queue.noteExpiryWarning(
        now: DateTime.now().subtract(const Duration(hours: warning + 1)),
      );
      final service = QueueSyncService(
        queue: queue,
        api: _Server(error: const SocketException('no signal')),
      );
      addTearDown(service.dispose);

      // The whole sync, with no network: this must work offline.
      service.start();
      for (var i = 0; i < 200 && (await queue.pending()).isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      expect(await queue.pending(), isEmpty);
    });

    Future<void> ageRow(String id, Duration age) async {
      final db = await databaseFactoryFfi.openDatabase('${dbDir.path}/outbox.db');
      await db.update(
        'referral_outbox',
        {'created_at': DateTime.now().subtract(age).toIso8601String()},
        where: 'client_request_id = ?',
        whereArgs: [id],
      );
    }

    testWidgets('Home warns the CHO, and the card opens the list', (tester) async {
      useTallScreen(tester);
      await tester.runAsync(() async {
        await queue.enqueue(_sample('a'));
        await ageRow('a', const Duration(hours: ttl - 1));
      });
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(api: _Server(), queue: queue, acousticEnabled: false)),
      );
      await settle(tester);
      // Warnings are behind one summary banner on Home.
      await tester.tap(find.byKey(const Key('home_warnings_summary')));
      await tester.pump();

      expect(
        find.text('1 unsent referral will soon be deleted from this phone'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        expect((await queue.pending()).single.expiryWarnedAt, isNotNull);
      });
      await tester.tap(find.byKey(const Key('home_expiring')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(UnsentReferralsScreen), findsOneWidget);
    });

    testWidgets('setup warns too, for a CHO who was sent back there', (tester) async {
      useTallScreen(tester);
      await tester.runAsync(() async {
        await queue.enqueue(_sample('a'));
        await ageRow('a', const Duration(hours: ttl - 1));
      });
      await tester.pumpWidget(
        MaterialApp(home: SetupScreen(onComplete: (_) {}, api: _Server(), queue: queue)),
      );
      await settle(tester);

      expect(find.textContaining('1 will soon be deleted'), findsOneWidget);
      await tester.runAsync(() async {
        expect((await queue.pending()).single.expiryWarnedAt, isNotNull);
      });
    });

    testWidgets('the unsent list refreshes after a referral is marked handled',
        (tester) async {
      useTallScreen(tester);
      await tester.runAsync(() async {
        await queue.enqueue(_sample('a'));
        await queue.flush(_Server(error: ApiException(404, _ours)));
      });
      await tester.pumpWidget(MaterialApp(home: UnsentReferralsScreen(queue: queue)));
      await settle(tester);
      await tester.tap(find.byKey(const Key('unsent_a')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('mark_handled_a')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('mark_handled_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);

      expect(find.byKey(const Key('unsent_a')), findsNothing);
    });

    testWidgets('Home says nothing about a fresh referral', (tester) async {
      useTallScreen(tester);
      await tester.runAsync(() => queue.enqueue(_sample('a')));
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(api: _Server(), queue: queue, acousticEnabled: false)),
      );
      await settle(tester);
      expect(find.byKey(const Key('home_expiring')), findsNothing);
    });
  });
}

class _Recording extends _Server {
  _Recording(this.bodies);

  final List<String> bodies;

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    bodies.add(req.toJson().toString());
    return super.createReferral(req);
  }
}
