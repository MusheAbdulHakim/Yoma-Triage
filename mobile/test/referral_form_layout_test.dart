import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

import 'helpers/cho_helper.dart';

const _vitals = {
  'systolic_bp': 120,
  'diastolic_bp': 80,
  'heart_rate': 80,
  'respiratory_rate': 18,
  'temperature': 37.0,
  'spo2': 98,
  'consciousness_level': 'A',
};

Future<void> _open(WidgetTester tester,
    {required Size size, double textScale = 1, Map<String, Object?>? vitals}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildYomaTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: ReferralScreen(initialVitals: vitals),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(registeredChoPrefs()));

  testWidgets('one bottom button: "Send now (vitals not taken)" until vitals are recorded',
      (tester) async {
    await _open(tester, size: const Size(360, 640));
    expect(find.byType(FilledButton), findsOneWidget, reason: 'no separate skip button');
    expect(find.text('Send now (vitals not taken)'), findsOneWidget);
    expect(find.textContaining('Not recorded – Record vitals'), findsOneWidget);
    expect(find.byKey(const Key('referral_send_to_confirm')), findsOneWidget);
    expect(find.text('Using Home CHPS location'), findsNothing);
  });

  testWidgets('with vitals recorded the button reads "Send referral"', (tester) async {
    await _open(tester, size: const Size(360, 640), vitals: _vitals);
    expect(find.text('Send referral'), findsOneWidget);
    expect(find.textContaining('Not recorded'), findsNothing);
  });

  for (final (size, scale) in [
    (const Size(360, 640), 1.0),
    (const Size(320, 568), 1.3),
  ]) {
    testWidgets('nothing hides behind the bottom area at ${size.width} dp, ${scale}x text',
        (tester) async {
      await _open(tester, size: size, textScale: scale);
      final bottomTop = tester.getRect(find.byKey(const Key('referral_send'))).top;
      for (final key in [
        'referral_type_pph',
        'referral_type_neonatal_asphyxia',
        'referral_send_to',
        'referral_vitals_summary',
      ]) {
        final target = find.byKey(Key(key));
        await tester.scrollUntilVisible(target, 50, scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        final rect = tester.getRect(target);
        expect(rect.bottom, lessThanOrEqualTo(bottomTop - 8), reason: '$key fully above Send');
        expect(target.hitTestable(), findsOneWidget, reason: key);
      }
    });
  }
}
