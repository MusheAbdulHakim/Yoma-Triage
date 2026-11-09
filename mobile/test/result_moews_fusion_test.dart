import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/screening_result.dart';

import 'helpers/vitals_helper.dart';

void main() {
  _neverGatedTests();

  testWidgets('GREEN acoustic + RED MOEWS shows Confirm Referral',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          result: ScreeningResult(
            label: 'GREEN',
            confidence: 0.6,
            reason: 'ok',
            source: 'yamnet',
          ),
          moews: const MoewsResult(score: 6, riskLevel: 'RED', hrScore: 3),
        ),
      ),
    );

    expect(find.text('Confirm Referral'), findsOneWidget);
    expect(find.text('MOEWS RED'), findsOneWidget);
    expect(find.textContaining('Acoustic (advisory)'), findsOneWidget);
    expect(find.textContaining('Heart rate contributes MOEWS'), findsOneWidget);
  });

  testWidgets('vitals are scored before showing the acoustic result',
      (tester) async {
    final result = ScreeningResult(
      label: 'GREEN',
      confidence: 0.6,
      reason: 'ok',
      source: 'yamnet',
    );
    useTallScreen(tester);
    await tester.pumpWidget(MaterialApp(home: VitalsScreen(result: result)));

    await fillVitals(tester, overrides: {'sbp': '70'});
    await tester.tap(find.byKey(const Key('vitals_see_result')));
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Confirm Referral'), findsOneWidget);
  });

  testWidgets('completed screening opens vitals before result', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ScreeningScreen(forceWebSimulator: true)),
    );

    await tester.tap(find.text('Demo Normal'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('Record vitals'), findsOneWidget);
    expect(find.text('Result'), findsNothing);
  });

  testWidgets('screening-session vitals prefill the referral form',
      (tester) async {
    useTallScreen(tester);
    final result = ScreeningResult(
      label: 'GREEN',
      confidence: 0.6,
      reason: 'ok',
      source: 'yamnet',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          result: result,
          moews: const MoewsResult(score: 3, riskLevel: 'RED'),
          vitals: const {
            'systolic_bp': 70,
            'diastolic_bp': 80,
            'heart_rate': 80,
            'respiratory_rate': 18,
            'temperature': 37.0,
            'spo2': 98,
            'consciousness_level': 'A',
          },
        ),
      ),
    );

    await tester.tap(find.text('Confirm Referral'));
    await tester.pumpAndSettle();

    final sbp = tester.widget<TextFormField>(
      find.byKey(const Key('referral_sbp')),
    );
    expect(sbp.controller?.text, '70');
  });
}

void _neverGatedTests() {
  testWidgets('MOEWS GREEN still lets the CHO refer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          result: ScreeningResult(
            label: 'GREEN',
            confidence: 0.9,
            reason: 'simulated',
            source: 'simulator',
          ),
          moews: const MoewsResult(score: 0, riskLevel: 'GREEN'),
        ),
      ),
    );

    expect(find.text('Continue Monitoring'), findsOneWidget);
    expect(find.text('Refer with clinical judgment'), findsOneWidget);
  });
}
