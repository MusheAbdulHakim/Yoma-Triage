// Copy rules: words, not codes; plurals; friendly dates; no repeated header; no debug
// line on Home outside test builds.
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/models/emergency_type.dart';

void main() {
  test('every emergency type reads as words, never its code', () {
    for (final (code, label) in emergencyTypes) {
      expect(emergencyTypeLabel(code), label);
      expect(label.contains('_'), isFalse, reason: label);
      expect(label, isNot(code));
    }
    expect(emergencyTypeLabel('pph'), 'Heavy bleeding');
    expect(emergencyTypeLabel(null), 'Emergency');
    expect(emergencyTypeLabel('something_new'), 'Emergency');
  });
}
