import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/main.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/cho_helper.dart';

const _acousticDefined = String.fromEnvironment('MOEWS_ONLY') == 'false';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(registeredChoPrefs());
  });

  testWidgets('Home hides acoustic screening by default', skip: _acousticDefined,
      (tester) async {
    await tester.pumpWidget(const YomaApp());
    await tester.pumpAndSettle();
    expect(find.text('Screen Breathing'), findsNothing);
    expect(find.text('Record Vitals'), findsOneWidget);
    expect(find.text('Emergency Referral'), findsOneWidget);
  });

  testWidgets('Home shows Screen Breathing when explicitly enabled',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(acousticEnabled: true)),
    );
    expect(find.text('Screen Breathing'), findsOneWidget);
    expect(find.text('Record Vitals'), findsNothing);
    expect(find.text('Emergency Referral'), findsOneWidget);
  });

  testWidgets('Record Vitals goes straight to vitals, no recording',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(acousticEnabled: false)),
    );
    await tester.tap(find.text('Record Vitals'));
    await tester.pumpAndSettle();
    expect(find.text('Continue to Result'), findsOneWidget);
    expect(find.text('Stop & Analyze Early'), findsNothing);
  });

  testWidgets('Emergency Referral bypasses screening', (tester) async {
    await tester.pumpWidget(const YomaApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emergency Referral'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vitals'), findsWidgets);
  });
}
