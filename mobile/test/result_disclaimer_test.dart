import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

const _advisory = 'Advisory only — not a diagnosis. Not clinically validated.';
const _signoff = 'Score thresholds pending clinical sign-off.';

Map<String, Object?> _vitals({int? spo2 = 98}) => {
      'systolic_bp': 118,
      'diastolic_bp': 76,
      'heart_rate': 72,
      'respiratory_rate': 16,
      'temperature': 36.8,
      'spo2': spo2,
      'consciousness_level': 'A',
    };

ResultScreen _scored({ScreeningResult? screening, int? spo2 = 98}) {
  final v = _vitals(spo2: spo2);
  return ResultScreen(
    result: screening ?? moewsOnlyResult(),
    vitals: v,
    moews: calculateMoews(
        sbp: 118, dbp: 76, hr: 72, rr: 16, temp: 36.8, spo2: spo2, consciousness: 'A'),
  );
}

void main() {
  testWidgets('breathing-only result keeps the advisory wording', (tester) async {
    final result = ScreeningResult(
      label: 'GREEN',
      confidence: 0.9,
      reason: 'Normal breathing pattern',
      source: 'yamnet',
    );
    await tester.pumpWidget(MaterialApp(home: ResultScreen(result: result)));
    expect(find.text(_advisory), findsOneWidget);
    expect(find.text(_signoff), findsNothing, reason: 'no vitals score here');
  });

  testWidgets('vitals result: one small sign-off line below Why, nothing above the card',
      (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildYomaTheme(), home: _scored()));
    final note = find.byKey(const Key('result_signoff_note'));
    expect(find.text(_signoff), findsOneWidget);
    expect(find.text(_advisory), findsNothing, reason: 'advisory wording is for breathing only');
    final card = tester.getRect(find.byKey(const Key('result_risk_card')));
    final why = tester.getRect(find.text('Why'));
    expect(tester.getRect(note).top, greaterThan(why.bottom));
    expect(tester.getRect(note).top, greaterThan(card.bottom));
  });

  testWidgets('with a breathing check, the advisory wording sits with the breathing row',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildYomaTheme(),
      home: _scored(
          screening: ScreeningResult(
              label: 'RED', confidence: 0.8, reason: 'x', source: 'yamnet', modelVersion: 't')),
    ));
    expect(find.text(_signoff), findsOneWidget);
    final row = tester.getRect(find.byKey(const Key('result_breathing_advisory')));
    final advisory = tester.getRect(find.text(_advisory));
    expect(advisory.top, greaterThanOrEqualTo(row.bottom));
  });

  testWidgets('stub source shows demo screening mode', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ResultScreen(result: stubClassify())));
    expect(find.textContaining('Demo screening mode.'), findsOneWidget);
  });

  testWidgets('simulator source shows demo screening mode', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: ResultScreen(result: simulatorClassify(forceRed: true))));
    expect(find.textContaining('Demo screening mode.'), findsOneWidget);
  });

  testWidgets('yamnet source does not show demo mode', (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: ResultScreen(result: mapYamnetToResult(abnormalScore: 0.82))));
    expect(find.textContaining('Demo screening mode.'), findsNothing);
  });
}
