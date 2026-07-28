import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/models/referral.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/offline_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.shouldFail = false});

  final bool shouldFail;
  int calls = 0;
  String? lastClientRequestId;
  String? lastAiModelVersion;

  @override
  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    calls++;
    lastClientRequestId = req.clientRequestId;
    lastAiModelVersion = req.aiModelVersion;
    if (shouldFail) throw ApiException(503, 'down');
    return {
      'referral': {'id': 1, 'client_request_id': req.clientRequestId},
      'dispatch': {'id': 9, 'status': 'TIER1_NOTIFIED'},
    };
  }
}

ReferralRequest _sample({required String id}) => ReferralRequest(
      clientRequestId: id,
      chpsCompoundId: 1,
      facilityId: 1,
      patientHash: 'a' * 64,
      emergencyType: 'respiratory_distress',
      vitals: {
        'systolic_bp': 70,
        'diastolic_bp': 50,
        'heart_rate': 140,
        'respiratory_rate': 35,
        'temperature': 39.5,
        'spo2': 85,
        'consciousness_level': 'V',
      },
      aiScreenResult: 'RED',
      aiConfidence: 0.82,
      aiModelVersion: 'yamnet-audioset-v0',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var dbCounter = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dbCounter++;
  });

  OfflineQueue testQueue() => OfflineQueue(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePathOverride: 'test_outbox_$dbCounter.db',
      );

  test('enqueue then flush marks sent and keeps client_request_id', () async {
    final queue = testQueue();
    final api = _FakeApi();
    const id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    await queue.enqueue(_sample(id: id));
    expect(await queue.pending(), hasLength(1));

    final sent = await queue.flush(api);
    expect(sent, 1);
    expect(api.calls, 1);
    expect(api.lastClientRequestId, id);
    expect(api.lastAiModelVersion, 'yamnet-audioset-v0');
    expect(await queue.pending(), isEmpty);
  });

  test('enqueue payload excludes patient_name', () async {
    final queue = testQueue();
    const id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    final req = _sample(id: id);
    expect(req.toJson().containsKey('patient_name'), isFalse);
    await queue.enqueue(req);
    final pending = await queue.pending();
    expect(pending.first.payload.containsKey('patient_name'), isFalse);
  });

  test('flush failure keeps pending — never silent-drop', () async {
    final queue = testQueue();
    final api = _FakeApi(shouldFail: true);
    const id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    await queue.enqueue(_sample(id: id));

    final sent = await queue.flush(api);
    expect(sent, 0);
    expect(api.calls, 1);
    final pending = await queue.pending();
    expect(pending, hasLength(1));
    expect(pending.first.clientRequestId, id);
    expect(pending.first.lastError, isNotNull);
  });

  test('flush persists dispatch_id for rebound polling', () async {
    final queue = testQueue();
    final api = _FakeApi();
    const id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
    await queue.enqueue(_sample(id: id));
    await queue.flush(api);
    expect(await queue.lookupDispatchId(id), 9);
  });
}
