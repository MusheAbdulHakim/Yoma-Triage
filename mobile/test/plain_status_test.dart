// A4: the screen shows where a referral really is, and errors are plain words with a
// next step, never an exception.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yoma_triage/models/referral.dart';
import 'package:yoma_triage/screens/dispatch_status_screen.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:yoma_triage/screens/stale_referral_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/offline_queue.dart';
import 'package:yoma_triage/services/screening_service.dart';
import 'package:yoma_triage/widgets/manual_contacts_panel.dart';

import 'helpers/cho_helper.dart';

const _id = 'req-1';

ReferralRequest _sample() => ReferralRequest(
      clientRequestId: _id,
      chpsCompoundId: 1,
      facilityId: 1,
      patientHash: 'h',
      choPhone: testChoPhone,
      emergencyType: 'pph',
      vitals: const {},
    );

/// The network error a phone really gets when the server is down.
final _refused = http.ClientException(
  'SocketException: Connection refused (OS Error: Connection refused, errno = 111), '
  'address = 10.0.2.2, port = 37872',
  Uri.parse('http://10.0.2.2:8000/api/v1/dispatch/7'),
);

class _Server extends ApiClient {
  bool offline = false;
  bool staleReply = false;
  bool dispatchDown = false;

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    if (offline) throw const SocketException('no signal');
    return {
      'referral': {'id': 42, 'status': staleReply ? 'AWAITING_CONFIRMATION' : 'CONFIRMED'},
      'dispatch': staleReply ? null : {'id': 7, 'status': 'TIER1_NOTIFIED'},
    };
  }

  @override
  Future<Map<String, dynamic>> getDispatch(int id) async {
    if (dispatchDown) throw _refused;
    return {'id': id, 'status': 'TIER1_NOTIFIED', 'current_tier': 1, 'facility_id': 1};
  }

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

/// Lets real async work (the database, the fake server) and the screen both move on.
Future<void> _settleReal(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final steps = duration.inMilliseconds ~/ 50;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late OfflineQueue queue;
  late _Server server;

  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues(registeredChoPrefs());
    final dir = Directory.systemTemp.createTempSync('yoma_plain');
    addTearDown(() => dir.deleteSync(recursive: true));
    queue = OfflineQueue(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: '${dir.path}/outbox.db',
    );
    server = _Server();
  });

  Future<void> openQueued(WidgetTester tester) async {
    await tester.runAsync(() => queue.enqueue(_sample()));
    await tester.pumpWidget(
      MaterialApp(home: QueuedReferralScreen(clientRequestId: _id, queue: queue, api: server)),
    );
    await tester.pump();
  }

  group('the queued screen follows a send that happens by itself', () {
    testWidgets('signal returns and it sends: the screen shows drivers notified',
        (tester) async {
      await openQueued(tester);
      expect(find.textContaining('Drivers have not been notified'), findsOneWidget);

      // As the sync service does when signal returns. Nothing on screen is tapped.
      await tester.runAsync(() => queue.flush(server));
      await _settleReal(tester);

      expect(find.byType(DispatchStatusScreen), findsOneWidget);
      expect(find.textContaining('Drivers have not been notified'), findsNothing);
      expect(find.byKey(const Key('dispatch_status_TIER1_NOTIFIED')), findsOneWidget);
    });

    testWidgets('a stale reply opens the question', (tester) async {
      server.staleReply = true;
      await openQueued(tester);
      await tester.runAsync(() => queue.flush(server));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.byType(StaleReferralScreen), findsOneWidget);
    });

    testWidgets('still no signal: it stays, and says nothing new', (tester) async {
      server.offline = true;
      await openQueued(tester);
      await tester.runAsync(() => queue.flush(server));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.byType(QueuedReferralScreen), findsOneWidget);
      expect(find.textContaining('Still waiting for coverage'), findsNothing);
    });
  });

  group('server unreachable on the dispatch screen', () {
    Future<void> openDispatch(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: DispatchStatusScreen(
            dispatchId: 7,
            clientRequestId: _id,
            api: server,
            queue: queue,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    testWidgets('says so plainly, with Call and SMS, and no error text', (tester) async {
      server.dispatchDown = true;
      await openDispatch(tester);

      expect(find.text(dispatchUnreachableMessage), findsOneWidget);
      for (final raw in ['SocketException', 'ClientException', 'errno', '10.0.2.2', 'Polling']) {
        expect(find.textContaining(raw), findsNothing, reason: raw);
      }
      expect(find.byType(ManualContactsPanel), findsOneWidget);
    });

    testWidgets('when the server is back, the status returns and the panel goes',
        (tester) async {
      server.dispatchDown = true;
      await openDispatch(tester);
      server.dispatchDown = false;
      // The next check backs off to 4 s after a failure.
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      expect(find.byKey(const Key('dispatch_status_TIER1_NOTIFIED')), findsOneWidget);
      expect(find.text(dispatchUnreachableMessage), findsNothing);
      expect(find.byType(ManualContactsPanel), findsNothing);
    });
  });

  group('microphone errors', () {
    test('permission and other failures each get plain words', () {
      expect(
        plainMicrophoneError(StateError('Microphone permission denied')),
        'Microphone permission is off.',
      );
      expect(plainMicrophoneError(StateError('no microphone')), 'The microphone could not start.');
    });

    testWidgets('the screen never shows the exception', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScreeningScreen(forceWebSimulator: false, service: _PermissionDenied()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Microphone not allowed'), findsOneWidget);
      expect(find.textContaining('Bad state'), findsNothing);
      expect(find.textContaining('Settings'), findsOneWidget);
      expect(find.byKey(const Key('screening_open_settings')), findsOneWidget);
    });
  });

  test('no screen puts an exception into its text', () {
    for (final file in Directory('lib/screens').listSync().whereType<File>()) {
      final source = file.readAsStringSync();
      for (final raw in [r"($e)", r": $e'", r"$error'", r"${e}"]) {
        expect(source.contains(raw), isFalse, reason: '${file.path} shows $raw');
      }
    }
  });
}

class _PermissionDenied extends ScreeningService {
  @override
  Future<void> startRecording() async => throw StateError('Microphone permission denied');
}
