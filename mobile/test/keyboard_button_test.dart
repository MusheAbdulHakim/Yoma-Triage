import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

import 'helpers/cho_helper.dart';

/// Found on the emulator (round 6): with the keyboard up, the main button sat under it,
/// because it was the Scaffold's bottomNavigationBar. It must ride above the keyboard.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(registeredChoPrefs()));

  Future<double> visibleBottomWithKeyboard(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildYomaTheme(), home: screen));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260); // a 260 dp keyboard
    await tester.pump();
    return 640 - 260;
  }

  testWidgets('Record vitals: See result stays above the keyboard', (tester) async {
    final visible =
        await visibleBottomWithKeyboard(tester, VitalsScreen(result: moewsOnlyResult()));
    final button = tester.getRect(find.byKey(const Key('vitals_see_result')));
    expect(button.bottom, lessThanOrEqualTo(visible));
    expect(find.byKey(const Key('vitals_see_result')).hitTestable(), findsOneWidget);
    // The focused field can still be scrolled into the space above the keyboard.
    final field = find.byKey(const Key('vitals_spo2'));
    await tester.ensureVisible(field);
    await tester.pump();
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(button.top));
  });

  testWidgets('Referral form: Send stays above the keyboard', (tester) async {
    final visible = await visibleBottomWithKeyboard(tester, const ReferralScreen());
    expect(
        tester.getRect(find.byKey(const Key('referral_send'))).bottom, lessThanOrEqualTo(visible));
  });
}
