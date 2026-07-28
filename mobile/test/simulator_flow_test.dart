import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/main.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 100),
  int maxSteps = 40,
}) async {
  for (var i = 0; i < maxSteps; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('screening early-stop GREEN shows Continue Monitoring primary',
      (tester) async {
    await tester.pumpWidget(const YomaApp());
    await tester.tap(find.text('Screen Breathing'));
    // Screening starts recording + breath pulse (infinite animation).
    await pumpUntilFound(tester, find.text('Stop & Analyze Early'));
    expect(find.text('Stop & Analyze Early'), findsOneWidget);
    expect(find.byKey(const Key('breathing_pulse')), findsOneWidget);

    await tester.tap(find.text('Stop & Analyze Early'));
    await tester.pump();
    expect(find.byKey(const Key('breathing_pulse')), findsOneWidget);
    await pumpUntilFound(tester, find.text('Continue to Result'));
    expect(find.text('Record Vitals'), findsOneWidget);
    await tester.tap(find.text('Continue to Result'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Continue Monitoring'));
    expect(find.text('Continue Monitoring'), findsWidgets);
    // GREEN path: Confirm Referral must not be the only/primary path.
    expect(find.text('Confirm Referral'), findsNothing);
  });

  testWidgets('RED result shows Confirm Referral', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          result: ScreeningResult(
            label: 'RED',
            confidence: 0.9,
            reason: 'test',
            source: 'simulator',
          ),
        ),
      ),
    );

    expect(find.text('Confirm Referral'), findsOneWidget);
  });

  testWidgets('INCONCLUSIVE result offers clinical judgment referral',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          result: ScreeningResult(
            label: 'INCONCLUSIVE',
            confidence: 0.4,
            reason: 'test',
            source: 'simulator',
          ),
        ),
      ),
    );

    expect(find.text('Continue Monitoring'), findsOneWidget);
    expect(find.text('Refer with clinical judgment'), findsOneWidget);
    expect(find.text('Confirm Referral'), findsNothing);
  });
}
