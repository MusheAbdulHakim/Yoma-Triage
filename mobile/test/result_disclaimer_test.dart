import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('always shows advisory disclaimer', (tester) async {
    final result = ScreeningResult(
      label: 'GREEN',
      confidence: 0.9,
      reason: 'Normal breathing pattern',
      source: 'yamnet',
    );
    await tester.pumpWidget(
      MaterialApp(home: ResultScreen(result: result)),
    );
    expect(
      find.text('Advisory only — not a diagnosis. Not clinically validated.'),
      findsOneWidget,
    );
  });

  testWidgets('stub source shows demo screening mode', (tester) async {
    final result = stubClassify(forceRed: false);
    await tester.pumpWidget(
      MaterialApp(home: ResultScreen(result: result)),
    );
    expect(find.text('Demo screening mode.'), findsOneWidget);
  });

  testWidgets('simulator source shows demo screening mode', (tester) async {
    final result = simulatorClassify(forceRed: true);
    await tester.pumpWidget(
      MaterialApp(home: ResultScreen(result: result)),
    );
    expect(find.text('Demo screening mode.'), findsOneWidget);
  });

  testWidgets('yamnet source does not show demo mode banner', (tester) async {
    final result = mapYamnetToResult(abnormalScore: 0.82);
    await tester.pumpWidget(
      MaterialApp(home: ResultScreen(result: result)),
    );
    expect(find.text('Demo screening mode.'), findsNothing);
  });
}
