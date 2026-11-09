import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/vitals_helper.dart';
import 'helpers/cho_helper.dart';

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
    SharedPreferences.setMockInitialValues(registeredChoPrefs());
  });

  testWidgets('screening early-stop is never GREEN; offers clinical judgment',
      (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(acousticEnabled: true)),
    );
    await tester.tap(find.text('Check breathing'));
    // Round 7 default: the Ready step first, then Start begins recording.
    await pumpUntilFound(tester, find.byKey(const Key('screening_start')));
    await tester.tap(find.byKey(const Key('screening_start')));
    // Screening starts recording + breath pulse (infinite animation).
    await pumpUntilFound(tester, find.byKey(const Key('screening_stop')));
    expect(find.byKey(const Key('screening_stop')), findsOneWidget);
    expect(find.byKey(const Key('breathing_pulse')), findsOneWidget);

    await tester.tap(find.byKey(const Key('screening_stop')));
    await tester.pump();
    // Round 7 default: the breathing result step, then on to vitals.
    await pumpUntilFound(tester, find.byKey(const Key('screening_continue_to_vitals')));
    await tester.tap(find.byKey(const Key('screening_continue_to_vitals')));
    await pumpUntilFound(tester, find.byKey(const Key('vitals_see_result')));
    expect(find.widgetWithText(AppBar, 'Record vitals'), findsOneWidget);
    await fillVitals(tester);
    await tester.tap(find.byKey(const Key('vitals_see_result')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Continue monitoring'));
    expect(find.text('Continue monitoring'), findsWidgets);
    expect(find.text('Confirm referral'), findsOneWidget);
  });

  testWidgets('RED result shows Confirm referral', (tester) async {
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

    expect(find.text('Confirm referral'), findsOneWidget);
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

    expect(find.text('Continue monitoring'), findsOneWidget);
    // Monitoring leads; referring stays one tap away as the secondary action.
    expect(find.text('Confirm referral'), findsOneWidget);
  });
}
