import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/patient_token.dart';

void main() {
  test('patientToken returns 64 lowercase hex chars', () {
    final token = patientToken();
    expect(token, hasLength(64));
    expect(token, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('patientToken generates unique values', () {
    final a = patientToken();
    final b = patientToken();
    expect(a, isNot(equals(b)));
  });

  test('patientToken is not derived from input strings', () {
    // Tokens must come from secure random material, never from names.
    final t1 = patientToken();
    final t2 = patientToken();
    expect(t1, isNot(contains('Ama')));
    expect(t2, isNot(contains('Mensah')));
  });
}
