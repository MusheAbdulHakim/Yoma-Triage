import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yoma_triage/models/referral.dart';
import 'package:yoma_triage/screens/failed_referrals_screen.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/offline_queue.dart';
import 'helpers/cho_helper.dart';
import 'helpers/vitals_helper.dart';

class _FailingApi extends ApiClient {
  _FailingApi(this.error);

  final Object error;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    calls++;
    throw error;
  }
}

ReferralRequest _sample(String id) => ReferralRequest(
      clientRequestId: id,
      chpsCompoundId: 1,
      facilityId: 1,
      patientHash: 'h',
      choPhone: '+233240000100',
      emergencyType: 'pph',
      vitals: const {'systolic_bp': 120},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late OfflineQueue queue;
  late Directory dbDir;

  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues(registeredChoPrefs());
    dbDir = Directory.systemTemp.createTempSync('yoma_permanent');
    addTearDown(() => dbDir.deleteSync(recursive: true));
    queue = OfflineQueue(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: '${dbDir.path}/outbox.db',
    );
  });

  group('classification', () {
    const ours = '{"detail":"x","code":"FACILITY_NOT_FOUND"}';
    for (final code in [400, 401, 403, 404, 409, 422, 499]) {
      test('$code with our error code is permanent', () {
        expect(ApiException(code, ours).isPermanent, isTrue);
        expect(ApiException(code, ours).needsRetryWarning, isFalse);
      });
      test('$code without it retries with a warning', () {
        expect(ApiException(code, '').isPermanent, isFalse);
        expect(ApiException(code, '').needsRetryWarning, isTrue);
      });
    }
    for (final body in [
      '<html>Log in to Wi-Fi</html>',
      '{"detail":"Not Found"}',
      '{"detail":"x","code":"SOME_PORTAL_CODE"}',
      '{"code":42}',
      '[1,2]',
    ]) {
      test('a 403 with $body is not trusted', () {
        expect(ApiException(403, body).isPermanent, isFalse);
        expect(ApiException(403, body).needsRetryWarning, isTrue);
      });
    }
    for (final code in [408, 429, 500, 502, 503, 504]) {
      test('$code is retried with no warning, even with a code', () {
        expect(ApiException(code, ours).isPermanent, isFalse);
        expect(ApiException(code, ours).needsRetryWarning, isFalse);
      });
    }
  });

  group('reason', () {
    test('uses a plain detail message', () {
      expect(
        ApiException(404, '{"detail":"Facility not found"}').reason,
        'Facility not found',
      );
    });

    test('uses the first validation message', () {
      expect(
        ApiException(422, '{"detail":[{"msg":"Input too large"}]}').reason,
        'Input too large',
      );
    });

    test('falls back to the status code for non-JSON', () {
      expect(ApiException(403, '<html>').reason, contains('HTTP 403'));
    });
  });

  group('flush', () {
    test('a permanent refusal is marked failed and never retried', () async {
      final api = _FailingApi(ApiException(404, '{"detail":"Facility not found","code":"FACILITY_NOT_FOUND"}'));
      await queue.enqueue(_sample('a'));

      await queue.flush(api);
      await queue.flush(api);

      expect(api.calls, 1);
      expect(await queue.pending(), isEmpty);
      final failed = await queue.failed();
      expect(failed.single.status, 'failed');
      expect(failed.single.lastError, 'Facility not found');
      expect(queue.failedCount.value, 1);
    });

    for (final code in [408, 429, 500, 503]) {
      test('$code stays pending and is retried', () async {
        final api = _FailingApi(ApiException(code, ''));
        await queue.enqueue(_sample('a'));

        await queue.flush(api);
        await queue.flush(api);

        expect(api.calls, 2);
        expect(await queue.pending(), hasLength(1));
        expect(await queue.failed(), isEmpty);
      });
    }

    test('a network error stays pending and is retried', () async {
      final api = _FailingApi(const SocketException('no route'));
      await queue.enqueue(_sample('a'));

      await queue.flush(api);
      await queue.flush(api);

      expect(api.calls, 2);
      expect(await queue.pending(), hasLength(1));
    });

    test('a non-JSON success (captive portal) stays pending', () async {
      final api = _FailingApi(const FormatException('<html>'));
      await queue.enqueue(_sample('a'));

      await queue.flush(api);

      expect(await queue.pending(), hasLength(1));
      expect(await queue.failed(), isEmpty);
    });
  });

  group('what the CHO sees', () {
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

    testWidgets('a refused referral says why and to call manually',
        (tester) async {
      final api = _FailingApi(ApiException(404, '{"detail":"Facility not found","code":"FACILITY_NOT_FOUND"}'));
      // Tall, so the whole not-sent-yet screen is built (its Retry sync now follows the
      // contacts).
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(home: ReferralScreen(queue: queue, api: api)),
      );
      await tester.tap(find.text('Emergency type'));
      await pumpUntil(tester, find.text('Heavy bleeding'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heavy bleeding').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('referral_send_to')));
      await pumpUntil(tester, find.text('Choose receiving facility'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('referral_send')));
      await pumpUntil(tester, find.byType(FailedReferralsScreen));
      await pumpUntil(tester, find.textContaining('Facility not found'));

      expect(find.byType(QueuedReferralScreen), findsNothing);
      expect(find.textContaining('Call the driver and the hospital'), findsOneWidget);
      expect(find.textContaining('Facility not found'), findsOneWidget);
    });

    testWidgets('a captive portal on a direct send keeps it queued and warns',
        (tester) async {
      final api = _FailingApi(ApiException(403, '<html>Log in to Wi-Fi</html>'));
      // Tall, so the whole not-sent-yet screen is built (its Retry sync now follows the
      // contacts).
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(home: ReferralScreen(queue: queue, api: api)),
      );
      await tester.tap(find.text('Emergency type'));
      await pumpUntil(tester, find.text('Heavy bleeding'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heavy bleeding').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('referral_send_to')));
      await pumpUntil(tester, find.text('Choose receiving facility'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('referral_send')));
      await pumpUntil(tester, find.byType(QueuedReferralScreen));
      await pumpUntil(tester, find.byKey(const Key('queued_retry_warning')));

      expect(find.byType(FailedReferralsScreen), findsNothing);
      await tester.runAsync(() async {
        expect(await queue.pending(), hasLength(1));
      });
    });

    testWidgets('a retry that gets refused also reaches the failed screen',
        (tester) async {
      final api = _FailingApi(ApiException(422, '{"detail":"Bad","code":"VALIDATION_ERROR"}'));
      await tester.runAsync(() => queue.enqueue(_sample('a')));
      // Tall, so the whole not-sent-yet screen is built (its Retry sync now follows the
      // contacts).
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: QueuedReferralScreen(
            clientRequestId: 'a',
            queue: queue,
            api: api,
          ),
        ),
      );

      await tester.tap(find.text('Retry sync'));
      await pumpUntil(tester, find.byType(FailedReferralsScreen));
    });

    testWidgets('a retryable error does not show as refused', (tester) async {
      final api = _FailingApi(ApiException(503, ''));
      await tester.runAsync(() => queue.enqueue(_sample('a')));
      // Tall, so the whole not-sent-yet screen is built (its Retry sync now follows the
      // contacts).
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: QueuedReferralScreen(
            clientRequestId: 'a',
            queue: queue,
            api: api,
          ),
        ),
      );

      await tester.tap(find.text('Retry sync'));
      await pumpUntil(tester, find.textContaining('Still waiting for coverage'));
      expect(find.byType(FailedReferralsScreen), findsNothing);
    });
  });
}
