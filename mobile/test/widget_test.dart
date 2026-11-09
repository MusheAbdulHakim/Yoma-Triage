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
    expect(find.text('Check breathing'), findsNothing);
    expect(find.text('Record vitals'), findsOneWidget);
    expect(find.text('Emergency referral'), findsOneWidget);
  });

  testWidgets('Home shows Check breathing when explicitly enabled',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(acousticEnabled: true)),
    );
    expect(find.text('Check breathing'), findsOneWidget);
    expect(find.text('Advisory'), findsOneWidget);
    expect(find.text('Record vitals'), findsNothing);
    expect(find.text('Emergency referral'), findsOneWidget);
  });

  testWidgets('Record Vitals goes straight to vitals, no recording',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(acousticEnabled: false)),
    );
    await tester.tap(find.text('Record vitals'));
    await tester.pumpAndSettle();
    expect(find.text('Continue to Result'), findsOneWidget);
    expect(find.text('Stop & Analyze Early'), findsNothing);
  });

  testWidgets('Emergency Referral bypasses screening', (tester) async {
    await tester.pumpWidget(const YomaApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emergency referral'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vitals'), findsWidgets);
  });
}
