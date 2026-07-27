import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/main.dart';
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

  testWidgets('screening early-stop shows Confirm Referral', (tester) async {
    await tester.pumpWidget(const YomaApp());
    await tester.tap(find.text('Screen Breathing'));
    // Screening starts recording + breath pulse (infinite animation).
    await pumpUntilFound(tester, find.text('Stop & Analyze Early'));
    expect(find.text('Stop & Analyze Early'), findsOneWidget);
    expect(find.byKey(const Key('breathing_pulse')), findsOneWidget);

    await tester.tap(find.text('Stop & Analyze Early'));
    await tester.pump();
    expect(find.byKey(const Key('breathing_pulse')), findsOneWidget);
    await pumpUntilFound(tester, find.text('Confirm Referral'));
    expect(find.text('Confirm Referral'), findsOneWidget);
  });
}
