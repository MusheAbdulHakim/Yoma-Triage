// UI redesign round 1: the Result screen's content comes from the app's own scoring.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/moews_explanation.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';
import 'package:yoma_triage/widgets/yoma_components.dart';

Map<String, Object?> _vitals({
  int? sbp = 120,
  int? dbp = 80,
  int? hr = 80,
  int? rr = 18,
  double? temp = 37.0,
  int? spo2 = 98,
  String? avpu = 'A',
}) =>
    {
      'systolic_bp': sbp,
      'diastolic_bp': dbp,
      'heart_rate': hr,
      'respiratory_rate': rr,
      'temperature': temp,
      'spo2': spo2,
      'consciousness_level': avpu,
    };

MoewsResult _score(Map<String, Object?> v) => calculateMoews(
      sbp: v['systolic_bp'] as int?,
      dbp: v['diastolic_bp'] as int?,
      hr: v['heart_rate'] as int?,
      rr: v['respiratory_rate'] as int?,
      temp: v['temperature'] as double?,
      spo2: v['spo2'] as int?,
      consciousness: v['consciousness_level'] as String?,
    );

Future<void> _open(WidgetTester tester, Map<String, Object?> vitals,
    {ScreeningResult? acoustic}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildYomaTheme(),
    home: ResultScreen(
      result: acoustic ?? moewsOnlyResult(),
      moews: _score(vitals),
      vitals: vitals,
    ),
  ));
}

String _primary(WidgetTester tester) {
  final button = tester.widget<FilledButton>(find.byKey(const Key('result_primary')));
  return (button.child! as Text).data!;
}

void main() {
  group('Why rows', () {
    test('critical first, labelled very high / very low; borderline high / low', () {
      final v = _vitals(sbp: 185, rr: 32, hr: 118);
      final rows = explainMoews(_score(v), v);
      expect(rows.map((r) => r.text), [
        'Systolic BP 185 mmHg – very high',
        'Breathing rate 32 per min – very high',
        'Heart rate 118 bpm – high',
      ]);
      expect(rows.map((r) => r.critical), [true, true, false]);
    });

    test('low readings say low', () {
      final v = _vitals(temp: 34.2, hr: 55, spo2: 92);
      final rows = explainMoews(_score(v), v);
      expect(rows.map((r) => r.text), [
        'Temperature 34.2 °C – very low',
        'Heart rate 55 bpm – low',
        'Oxygen saturation 92 % – low',
      ]);
    });

    test('a normal set has no rows', () {
      final v = _vitals();
      expect(explainMoews(_score(v), v), isEmpty);
    });
  });

  group('variants', () {
    testWidgets('RED: risk announced in words, Confirm referral leads', (tester) async {
      await _open(tester, _vitals(sbp: 185, rr: 32, hr: 118));
      final card = tester.getSemantics(find.byKey(const Key('result_risk_card')));
      expect(card.label, startsWith('Risk level: Critical.'));
      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('MOEWS RED'), findsOneWidget);
      expect(_primary(tester), 'Confirm referral');
      expect(find.text('Systolic BP 185 mmHg – very high'), findsOneWidget);
    });

    testWidgets('AMBER: Elevated, dark text on amber', (tester) async {
      await _open(tester, _vitals(hr: 118));
      expect(find.text('Elevated'), findsOneWidget);
      final word = tester.widget<Text>(find.text('Elevated'));
      expect(word.style?.color, TriageColors.onAmber);
      expect(_primary(tester), 'Confirm referral');
    });

    testWidgets('INCOMPLETE: grey dashed card, Not measured list, Confirm referral leads',
        (tester) async {
      await _open(tester, _vitals(sbp: null, dbp: null, temp: null, avpu: null));
      expect(find.text('Incomplete'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('result_risk_card')),
          matching:
              find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DashedBorderPainter),
        ),
        findsOneWidget,
      );
      final list = find.byKey(const Key('moews_not_measured'));
      expect(find.descendant(of: list, matching: find.text('Not measured')), findsOneWidget);
      // Systolic and diastolic missing together read as one row, as in the design.
      for (final name in ['Blood pressure', 'Temperature', 'Consciousness']) {
        expect(find.descendant(of: list, matching: find.text(name)), findsOneWidget);
      }
      expect(_primary(tester), 'Confirm referral');
    });

    testWidgets('GREEN: Continue monitoring leads, and missing SpO2 is said', (tester) async {
      await _open(tester, _vitals(spo2: null));
      expect(find.text('Stable'), findsOneWidget);
      expect(_primary(tester), 'Continue monitoring');
      expect(find.text('Oxygen saturation not measured'), findsOneWidget);
      expect(find.text('Confirm referral'), findsOneWidget);
    });

    testWidgets('breathing advisory row stays secondary: grey, words only, no triage colours',
        (tester) async {
      final acoustic = ScreeningResult(
        label: 'RED',
        confidence: 0.8,
        reason: 'Stridor-like sound',
        source: 'yamnet',
        modelVersion: 'yamnet-test',
      );
      await _open(tester, _vitals(), acoustic: acoustic);
      final row = find.byKey(const Key('result_breathing_advisory'));
      expect(find.descendant(of: row, matching: find.text('Breathing check (advisory)')),
          findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Possible breathing problem')),
          findsOneWidget);
      // No score or confidence.
      expect(find.textContaining('80%'), findsNothing);
      expect(find.textContaining('Confidence'), findsNothing);
      final triage = [TriageColors.red, TriageColors.amber, TriageColors.green];
      for (final text
          in tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))) {
        expect(triage.contains(text.style?.color), isFalse, reason: text.data);
      }
      // Below the Why list, clearly after the risk card.
      expect(tester.getRect(row).top,
          greaterThan(tester.getRect(find.byKey(const Key('result_risk_card'))).bottom));
    });
  });
}
