import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yoma_triage/models/referral.dart';
import 'package:yoma_triage/screens/dispatch_status_screen.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';
import 'package:yoma_triage/screens/stale_referral_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/offline_queue.dart';

import 'helpers/cho_helper.dart';

const _id = 'req-1';

ReferralRequest _sample({String id = _id}) => ReferralRequest(
      clientRequestId: id,
      chpsCompoundId: 1,
      facilityId: 1,
      patientHash: 'h',
      choPhone: testChoPhone,
      emergencyType: 'pph',
      vitals: const {},
    );

/// Answers like the real server: stale above the threshold it was told about.
class _Server extends ApiClient {
  static const staleAbove = 1200;

  final List<int?> ages = [];
  final List<bool> manualContacts = [];
  final List<Map<String, Object?>> resolves = [];
  final List<Map<String, Object?>> cancels = [];
  Object? resolveError;
  Object? cancelError;

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    ages.add(req.queueAgeSeconds);
    manualContacts.add(req.manualContact);
    final stale = (req.queueAgeSeconds ?? 0) > staleAbove || req.manualContact;
    return {
      'referral': {'id': 42, 'status': stale ? 'AWAITING_CONFIRMATION' : 'CONFIRMED'},
      'dispatch': stale ? null : {'id': 7, 'status': 'TIER1_NOTIFIED'},
    };
  }

  @override
  Future<Map<String, dynamic>> resolveReferral({
    required int referralId,
    required String action,
    required String choPhone,
  }) async {
    if (resolveError != null) throw resolveError!;
    resolves.add({'id': referralId, 'action': action, 'cho': choPhone});
    return {
      'referral': {'id': referralId},
      'dispatch': action == 'send_now' ? {'id': 7, 'status': 'TIER1_NOTIFIED'} : null,
    };
  }

  @override
  Future<Map<String, dynamic>> cancelDispatch({
    required int dispatchId,
    required String choPhone,
  }) async {
    if (cancelError != null) throw cancelError!;
    cancels.add({'id': dispatchId, 'cho': choPhone});
    return {'id': dispatchId, 'status': 'CANCELLED'};
  }

  @override
  Future<Map<String, dynamic>> getDispatch(int id) async => {
        'id': id,
        'status': 'TIER1_NOTIFIED',
        'current_tier': 1,
        'facility_id': 1,
      };

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

  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues(registeredChoPrefs());
    dbDir = Directory.systemTemp.createTempSync('yoma_stale');
    addTearDown(() => dbDir.deleteSync(recursive: true));
    queue = OfflineQueue(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: '${dbDir.path}/outbox.db',
    );
  });

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Lets database work started by a widget finish. It runs in the test's fake zone, so
  /// it needs pumps as well as real time. Awaiting the queue before this can deadlock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
  }

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

  /// Enqueues, then makes the row look older by moving its stored creation time back.
  Future<void> enqueueAged(Duration age, {String id = _id}) async {
    await queue.enqueue(_sample(id: id));
    final db = await databaseFactoryFfi.openDatabase('${dbDir.path}/outbox.db');
    await db.update(
      'referral_outbox',
      {'created_at': DateTime.now().subtract(age).toIso8601String()},
      where: 'client_request_id = ?',
      whereArgs: [id],
    );
  }

  group('queue age', () {
    test('sends how long it waited, measured on this phone', () async {
      final server = _Server();
      await enqueueAged(const Duration(minutes: 5));
      await queue.flush(server);

      expect(server.ages.single, inInclusiveRange(300, 310));
    });

    test('a clock set back reads as zero, never negative', () async {
      final server = _Server();
      await enqueueAged(const Duration(minutes: -30));
      await queue.flush(server);

      expect(server.ages.single, 0);
    });

    test('the JSON has an elapsed age and no timestamp', () {
      final json = ReferralRequest(
        clientRequestId: _id,
        chpsCompoundId: 1,
        facilityId: 1,
        patientHash: 'h',
        choPhone: testChoPhone,
        emergencyType: 'pph',
        vitals: const {},
        queueAgeSeconds: 61,
      ).toJson();
      expect(json['queue_age_seconds'], 61);
      expect(json.keys.where((k) => k.contains('created') || k.contains('time')), isEmpty);
    });

    test('a live send has no age, and local notes never reach the server', () async {
      expect(_sample().toJson().containsKey('queue_age_seconds'), isFalse);
      await queue.enqueue(_sample());
      await queue.markManualContact(_id);
      final item = (await queue.pending()).single;
      expect(item.manualContactMade, isTrue);
      String? sent;
      await queue.flush(_CapturingServer((json) => sent = json));
      expect(sent, isNot(contains('local_')));
    });
  });

  group('stale on sync', () {
    test('a stale referral waits for an answer and is not treated as sent', () async {
      await enqueueAged(const Duration(minutes: 30));
      final sent = await queue.flush(_Server());

      expect(sent, 0);
      expect(await queue.pending(), isEmpty);
      final waiting = await queue.needsConfirmation();
      expect(waiting.single.serverReferralId, 42);
      expect(queue.needsConfirmationCount.value, 1);
      expect(await queue.lookupDispatchId(_id), isNull);
    });

    test('a fresh referral is sent as before', () async {
      await enqueueAged(const Duration(minutes: 5));
      final sent = await queue.flush(_Server());

      expect(sent, 1);
      expect(await queue.needsConfirmation(), isEmpty);
      expect(await queue.lookupDispatchId(_id), 7);
    });

    test('a waiting referral is not sent again by the next flush', () async {
      await enqueueAged(const Duration(minutes: 30));
      final server = _Server();
      await queue.flush(server);
      await queue.flush(server);
      expect(server.ages, hasLength(1));
    });
  });

  group('the prompt', () {
    Future<_Server> pumpPrompt(WidgetTester tester, {_Server? server}) async {
      useTallScreen(tester);
      final api = server ?? _Server();
      await tester.runAsync(() async {
        await enqueueAged(const Duration(minutes: 30));
        await queue.flush(api);
      });
      await tester.pumpWidget(
        MaterialApp(home: StaleReferralScreen(queue: queue, api: api)),
      );
      await pumpUntil(tester, find.byKey(const Key('stale_confirm_$_id')));
      return api;
    }

    Future<void> choose(WidgetTester tester, String action) async {
      await tester.tap(find.byKey(Key('stale_${action}_$_id')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('stale_confirm_$_id')));
    }

    testWidgets('asks the question and offers the three answers', (tester) async {
      await pumpPrompt(tester);
      expect(find.text('Still needs transport?'), findsOneWidget);
      expect(find.text('Send now'), findsOneWidget);
      expect(find.text('Already handled'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('nothing is preselected unless the CHO called someone', (tester) async {
      await pumpPrompt(tester);
      final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('stale_confirm_$_id')),
      );
      expect(confirm.onPressed, isNull);
    });

    testWidgets('a Call or SMS tap preselects Already handled', (tester) async {
      useTallScreen(tester);
      final api = _Server();
      await tester.runAsync(() async {
        await enqueueAged(const Duration(minutes: 30));
        await queue.markManualContact(_id);
        await queue.flush(api);
      });
      await tester.pumpWidget(
        MaterialApp(home: StaleReferralScreen(queue: queue, api: api)),
      );
      await pumpUntil(tester, find.byKey(const Key('stale_confirm_$_id')));

      final tile = tester.widget<ListTile>(
        find.byKey(const Key('stale_already_handled_$_id')),
      );
      expect(tile.selected, isTrue);
      expect(find.byKey(const Key('stale_contact_note_$_id')), findsOneWidget);
      await tester.tap(find.byKey(const Key('stale_confirm_$_id')));
      await settle(tester);
      expect(api.resolves.single['action'], 'already_handled');
    });

    testWidgets('Send now dispatches and opens the status screen', (tester) async {
      final api = await pumpPrompt(tester);
      await choose(tester, 'send_now');
      await pumpUntil(tester, find.byType(DispatchStatusScreen));

      expect(api.resolves.single, {'id': 42, 'action': 'send_now', 'cho': testChoPhone});
      await tester.runAsync(() async {
        expect(await queue.needsConfirmation(), isEmpty);
        expect(await queue.lookupDispatchId(_id), 7);
      });
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Already handled is recorded and removes it', (tester) async {
      final api = await pumpPrompt(tester);
      await choose(tester, 'already_handled');
      await settle(tester);

      expect(api.resolves.single['action'], 'already_handled');
      await tester.runAsync(() async {
        expect(await queue.needsConfirmation(), isEmpty);
      });
    });

    testWidgets('Cancel is recorded and removes it', (tester) async {
      final api = await pumpPrompt(tester);
      await choose(tester, 'cancel');
      await settle(tester);

      expect(api.resolves.single['action'], 'cancel');
      await tester.runAsync(() async {
        expect(await queue.needsConfirmation(), isEmpty);
      });
    });

    testWidgets('no connection keeps the question and says the answer was not saved',
        (tester) async {
      final server = _Server()..resolveError = const SocketException('no signal');
      await pumpPrompt(tester, server: server);
      await choose(tester, 'cancel');
      await pumpUntil(tester, find.byKey(const Key('stale_problem_$_id')));

      expect(find.textContaining('your answer was not saved'), findsOneWidget);
      await tester.runAsync(() async {
        expect(await queue.needsConfirmation(), hasLength(1));
      });
    });

    testWidgets('if someone already answered, it is removed rather than stuck',
        (tester) async {
      final server = _Server()
        ..resolveError = ApiException(
          409,
          '{"detail":"Already recorded","code":"REFERRAL_ALREADY_RESOLVED"}',
        );
      await pumpPrompt(tester, server: server);
      await choose(tester, 'cancel');
      await settle(tester);
      await tester.runAsync(() async {
        expect(await queue.needsConfirmation(), isEmpty);
      });
    });
  });

  group('a referral the server closed after waiting unanswered (B4)', () {
    const expired = '{"detail":"This referral was closed after 24 hours without an answer. '
        'Drivers were not told. If transport is still needed, start a new Emergency Referral '
        'or phone a driver now.","code":"REFERRAL_EXPIRED"}';

    Future<void> pumpExpired(WidgetTester tester) async {
      useTallScreen(tester);
      final api = _Server();
      await tester.runAsync(() async {
        await enqueueAged(const Duration(minutes: 30));
        await queue.flush(api);
      });
      api.resolveError = ApiException(409, expired);
      await tester.pumpWidget(
        MaterialApp(home: StaleReferralScreen(queue: queue, api: api)),
      );
      await pumpUntil(tester, find.byKey(const Key('stale_confirm_$_id')));
    }

    Future<void> choose(WidgetTester tester, String action) async {
      await tester.tap(find.byKey(Key('stale_${action}_$_id')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('stale_confirm_$_id')));
    }

    testWidgets('Send now says drivers were not told, and waits to be read', (tester) async {
      await pumpExpired(tester);
      await choose(tester, 'send_now');
      await pumpUntil(tester, find.byKey(const Key('stale_expired_message')));

      expect(find.text('Drivers were not told'), findsOneWidget);
      expect(find.textContaining('start a new Emergency Referral'), findsOneWidget);
      // Still on this phone until the CHO has read it.
      await tester.runAsync(() async {
        expect(await queue.needsConfirmation(), hasLength(1));
      });

      await tester.tap(find.byKey(const Key('stale_expired_ok')));
      await settle(tester);
      await tester.runAsync(() async {
        expect(await queue.needsConfirmation(), isEmpty);
      });
      expect(find.byType(DispatchStatusScreen), findsNothing);
    });

    for (final action in ['already_handled', 'cancel']) {
      testWidgets('$action needs no message: nobody was told anyway', (tester) async {
        await pumpExpired(tester);
        await choose(tester, action);
        await settle(tester);

        expect(find.byKey(const Key('stale_expired_message')), findsNothing);
        await tester.runAsync(() async {
          expect(await queue.needsConfirmation(), isEmpty);
        });
      });
    }
  });

  group('how the prompt is reached', () {
    testWidgets('Home opens it when a stale referral arrives', (tester) async {
      useTallScreen(tester);
      final api = _Server();
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(api: api, queue: queue, acousticEnabled: false)),
      );
      await settle(tester);
      await tester.runAsync(() async {
        await enqueueAged(const Duration(minutes: 30));
        await queue.flush(api);
      });
      await pumpUntil(tester, find.byType(StaleReferralScreen));
      await pumpUntil(tester, find.byKey(const Key('stale_confirm_$_id')));
    });

    testWidgets('Home shows a card for one left waiting from an earlier session',
        (tester) async {
      useTallScreen(tester);
      final api = _Server();
      await tester.runAsync(() async {
        await enqueueAged(const Duration(minutes: 30));
        await queue.flush(api);
      });
      // needsConfirmationCount starts at 1 here because flush already set it.
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(api: api, queue: queue, acousticEnabled: false)),
      );
      // Warnings are behind one summary banner on Home.
      await pumpUntil(tester, find.byKey(const Key('home_warnings_summary')));
      await tester.tap(find.byKey(const Key('home_warnings_summary')));
      await pumpUntil(tester, find.byKey(const Key('home_stale_referrals')));
      await tester.tap(find.byKey(const Key('home_stale_referrals')));
      await pumpUntil(tester, find.byKey(const Key('stale_confirm_$_id')));
    });

    testWidgets('Retry sync on the queued screen goes straight to it', (tester) async {
      useTallScreen(tester);
      final api = _Server();
      await tester.runAsync(() => enqueueAged(const Duration(minutes: 30)));
      await tester.pumpWidget(
        MaterialApp(
          home: QueuedReferralScreen(clientRequestId: _id, queue: queue, api: api),
        ),
      );
      await tester.tap(find.text('Retry sync'));
      await pumpUntil(tester, find.byType(StaleReferralScreen));
    });

    testWidgets('a Call tap on the queued screen is remembered', (tester) async {
      useTallScreen(tester);
      SharedPreferences.setMockInitialValues({
        ...registeredChoPrefs(),
        'manual_contacts':
            '{"compound_id":1,"drivers":[{"name":"I","phone":"+233240000001","is_motor_king":true}],"facilities":[]}',
        'manual_contacts_updated_at': DateTime.utc(2026, 11, 5).toIso8601String(),
      });
      await tester.runAsync(() => queue.enqueue(_sample()));
      await tester.pumpWidget(
        MaterialApp(
          home: QueuedReferralScreen(
            clientRequestId: _id,
            queue: queue,
            api: _Server(),
            launcher: (_) async => true,
          ),
        ),
      );
      await pumpUntil(tester, find.byKey(const Key('call_+233240000001')));
      await tester.tap(find.byKey(const Key('call_+233240000001')));
      await settle(tester);
      await tester.runAsync(() async {
        expect((await queue.pending()).single.manualContactMade, isTrue);
      });
    });

    // B2: a Call or SMS means transport may already be coming, whatever the age.
    testWidgets('after a Call tap, a fresh referral asks first, with Already handled chosen',
        (tester) async {
      useTallScreen(tester);
      SharedPreferences.setMockInitialValues({
        ...registeredChoPrefs(),
        'manual_contacts':
            '{"compound_id":1,"drivers":[{"name":"I","phone":"+233240000001","is_motor_king":true}],"facilities":[]}',
        'manual_contacts_updated_at': DateTime.utc(2026, 11, 5).toIso8601String(),
      });
      final api = _Server();
      await tester.runAsync(() => queue.enqueue(_sample()));
      await tester.pumpWidget(
        MaterialApp(
          home: QueuedReferralScreen(
            clientRequestId: _id,
            queue: queue,
            api: api,
            launcher: (_) async => true,
          ),
        ),
      );
      await pumpUntil(tester, find.byKey(const Key('call_+233240000001')));
      await tester.tap(find.byKey(const Key('call_+233240000001')));
      await settle(tester);

      await tester.tap(find.text('Retry sync'));
      await pumpUntil(tester, find.byType(StaleReferralScreen));
      await pumpUntil(tester, find.byKey(const Key('stale_confirm_$_id')));

      expect(api.manualContacts, [true]);
      expect(api.ages.single, lessThan(_Server.staleAbove), reason: 'fresh, yet asked');
      final tile = tester.widget<ListTile>(find.byKey(const Key('stale_already_handled_$_id')));
      expect(tile.selected, isTrue);
    });

    testWidgets('without a Call or SMS, a fresh referral is sent straight on', (tester) async {
      final api = _Server();
      await tester.runAsync(() async {
        await queue.enqueue(_sample());
        await queue.flush(api);
      });
      expect(api.manualContacts, [false]);
      await tester.runAsync(() async {
        expect(await queue.needsConfirmation(), isEmpty);
        expect(await queue.lookupDispatchId(_id), 7);
      });
    });
  });

  group('cancel an active dispatch', () {
    Future<_Server> pumpStatus(WidgetTester tester, {_Server? server}) async {
      useTallScreen(tester);
      final api = server ?? _Server();
      await tester.pumpWidget(
        MaterialApp(
          home: DispatchStatusScreen(
            dispatchId: 7,
            clientRequestId: _id,
            api: api,
            queue: queue,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return api;
    }

    Future<void> tapCancel(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('dispatch_cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('dispatch_cancel_confirm')));
    }

    testWidgets('asks first, then cancels', (tester) async {
      final api = await pumpStatus(tester);
      await tapCancel(tester);
      await pumpUntil(tester, find.byKey(const Key('dispatch_status_CANCELLED')));

      expect(api.cancels.single, {'id': 7, 'cho': testChoPhone});
      expect(find.byKey(const Key('dispatch_cancel')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Keep it does nothing', (tester) async {
      final api = await pumpStatus(tester);
      await tester.tap(find.byKey(const Key('dispatch_cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Keep it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.cancels, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no connection says so and tells the CHO to call', (tester) async {
      final server = _Server()..cancelError = const SocketException('no signal');
      await pumpStatus(tester, server: server);
      await tapCancel(tester);
      await pumpUntil(tester, find.textContaining('Could not cancel'));

      expect(find.textContaining('Call the driver and hospital'), findsOneWidget);
      expect(find.byKey(const Key('dispatch_cancel')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a server refusal shows its reason', (tester) async {
      final server = _Server()
        ..cancelError = ApiException(
          409,
          '{"detail":"This dispatch is already COMPLETED.","code":"DISPATCH_NOT_CANCELLABLE"}',
        );
      await pumpStatus(tester, server: server);
      await tapCancel(tester);
      await pumpUntil(tester, find.text('This dispatch is already COMPLETED.'));
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _CapturingServer extends _Server {
  _CapturingServer(this.onBody);

  final void Function(String) onBody;

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    onBody(req.toJson().toString());
    return super.createReferral(req);
  }
}
