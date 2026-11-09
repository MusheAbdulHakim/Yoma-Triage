import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/referral_screen.dart';

import '../helpers/cho_helper.dart';
import 'shot.dart';

void main() {
  setUpAll(loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues(registeredChoPrefs()));
  testWidgets('form', (tester) async {
    await pumpPhone(tester, const ReferralScreen());
    await shot(tester, 'form_no_type');
    await tester.tap(find.byKey(const Key('referral_type_pph')));
    await settle(tester);
    await shot(tester, 'form_type_selected');
    await tester.pumpWidget(const SizedBox());
    await pumpPhone(
        tester,
        const ReferralScreen(initialVitals: {
          'systolic_bp': 165,
          'diastolic_bp': 112,
          'heart_rate': 118,
          'respiratory_rate': 24,
          'temperature': 37.0,
          'spo2': 95,
          'consciousness_level': 'A',
        }));
    await tester.tap(find.byKey(const Key('referral_type_pph')));
    await settle(tester);
    await shot(tester, 'form_with_vitals');
  });
}
