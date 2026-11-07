import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/vitals_helper.dart';
import 'helpers/cho_helper.dart';

/// Advance frames without [pumpAndSettle], which hangs on the breath pulse.
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
  // Final pump for any pending navigation.
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(registeredChoPrefs());
  });

  testWidgets('web simulator Code Red shows Confirm Referral', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: ScreeningScreen(forceWebSimulator: true),
      ),
    );
    expect(find.text('Demo Code Red'), findsOneWidget);
    await tester.tap(find.text('Demo Code Red'));
    await tester.pump();
    expect(find.byKey(const Key('breathing_pulse_rings')), findsOneWidget);
    await pumpUntilFound(tester, find.text('Continue to Result'));
    expect(find.text('Record Vitals'), findsOneWidget);
    await fillVitals(tester);
    await tester.tap(find.text('Continue to Result'));
    await tester.pumpAndSettle();
    // MOEWS leads the result; the acoustic RED appears as an advisory card.
    expect(find.text('MOEWS GREEN'), findsOneWidget);
    expect(find.text('Acoustic (advisory): RED'), findsOneWidget);
    expect(find.text('Confirm Referral'), findsOneWidget);
    expect(find.text('Continue Monitoring'), findsOneWidget);
    expect(find.byKey(const Key('breathing_pulse_rings')), findsNothing);
  });
}
