import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yoma_triage/models/referral.dart';
import 'package:yoma_triage/services/api_client.dart';

/// The real ApiClient against a fake transport. The server's side of each of these
/// requests is covered by tests/test_stale_referrals.py.
void main() {
  late http.Request sent;

  ApiClient clientReturning(int status, String body) => ApiClient(
        baseUrl: 'https://yoma.test',
        apiKey: 'key',
        client: MockClient((request) async {
          sent = request;
          return http.Response(body, status);
        }),
      );

  test('resolveReferral', () async {
    final response = await clientReturning(200, '{"referral":{"id":4},"dispatch":null}')
        .resolveReferral(referralId: 4, action: 'cancel', choPhone: '+233240000100');

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://yoma.test/api/v1/referral/4/resolve');
    expect(sent.headers['X-API-Key'], 'key');
    expect(jsonDecode(sent.body), {'action': 'cancel', 'cho_phone': '+233240000100'});
    expect(response['dispatch'], isNull);
  });

  test('cancelDispatch', () async {
    final response = await clientReturning(200, '{"id":7,"status":"CANCELLED"}')
        .cancelDispatch(dispatchId: 7, choPhone: '+233240000100');

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://yoma.test/api/v1/dispatch/7/cancel');
    expect(sent.headers['X-API-Key'], 'key');
    expect(jsonDecode(sent.body), {'cho_phone': '+233240000100'});
    expect(response['status'], 'CANCELLED');
  });

  test('createReferral sends the queue age', () async {
    await clientReturning(201, '{}').createReferral(
      ReferralRequest(
        clientRequestId: 'a',
        chpsCompoundId: 1,
        facilityId: 1,
        patientHash: 'h',
        choPhone: '+233240000100',
        emergencyType: 'pph',
        vitals: const {},
        queueAgeSeconds: 61,
      ),
    );
    expect(jsonDecode(sent.body)['queue_age_seconds'], 61);
    expect(jsonDecode(sent.body).containsKey('manual_contact'), isFalse);
  });

  test('createReferral says when the CHO called or texted someone (B2)', () async {
    await clientReturning(201, '{}').createReferral(
      ReferralRequest(
        clientRequestId: 'a',
        chpsCompoundId: 1,
        facilityId: 1,
        patientHash: 'h',
        choPhone: '+233240000100',
        emergencyType: 'pph',
        vitals: const {},
        queueAgeSeconds: 5,
        manualContact: true,
      ),
    );
    expect(jsonDecode(sent.body)['manual_contact'], isTrue);
  });

  for (final (name, call) in <(String, Future<void> Function(ApiClient))>[
    (
      'resolveReferral',
      (api) => api.resolveReferral(referralId: 1, action: 'cancel', choPhone: 'p'),
    ),
    ('cancelDispatch', (api) => api.cancelDispatch(dispatchId: 1, choPhone: 'p')),
  ]) {
    test('$name throws a refusal with its code', () async {
      final api = clientReturning(
        409,
        '{"detail":"Already recorded","code":"REFERRAL_ALREADY_RESOLVED"}',
      );
      await expectLater(
        call(api),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'REFERRAL_ALREADY_RESOLVED')
              .having((e) => e.reason, 'reason', 'Already recorded'),
        ),
      );
    });
  }
}
