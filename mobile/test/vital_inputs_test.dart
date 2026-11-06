import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/services/vital_limits.dart';

import 'helpers/vitals_helper.dart';

const _ids = ['sbp', 'dbp', 'hr', 'rr', 'temp', 'spo2'];

String _text(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

Future<void> _tickAllNotMeasured(WidgetTester tester, String prefix) async {
  for (final id in _ids) {
    await tester.tap(find.byKey(Key('${prefix}_${id}_not_measured')));
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('VitalsScreen', () {
    Future<void> open(WidgetTester tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(home: VitalsScreen(result: moewsOnlyResult())),
      );
    }

    testWidgets('every vital starts empty', (tester) async {
      await open(tester);
      for (final id in _ids) {
        expect(_text(tester, 'vitals_$id'), isEmpty, reason: id);
      }
      expect(find.text('A — Alert'), findsNothing);
    });

    testWidgets('untouched form cannot continue', (tester) async {
      await open(tester);
      await tester.tap(find.text('Continue to Result'));
      await tester.pumpAndSettle();
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.text('Enter a value or tick Not measured'), findsNWidgets(6));
      expect(find.text('Select AVPU or Not measured'), findsOneWidget);
    });

    testWidgets('all not measured gives MOEWS UNKNOWN', (tester) async {
      await open(tester);
      await _tickAllNotMeasured(tester, 'vitals');
      await selectAvpu(tester, avpu: 'Not measured');

      await tester.tap(find.text('Continue to Result'));
      await tester.pumpAndSettle();

      final result = tester.widget<ResultScreen>(find.byType(ResultScreen));
      expect(result.moews!.riskLevel, 'UNKNOWN');
      expect(result.vitals!['systolic_bp'], isNull);
      expect(result.vitals!['consciousness_level'], isNull);
      expect(result.vitals!.containsKey('systolic_bp'), isTrue);
      expect(find.text('MOEWS UNKNOWN'), findsOneWidget);
      expect(find.text('Refer with clinical judgment'), findsOneWidget);
    });

    testWidgets('AVPU not measured alone gives UNKNOWN, not Alert',
        (tester) async {
      await open(tester);
      await fillVitals(tester, avpu: 'Not measured');
      await tester.tap(find.text('Continue to Result'));
      await tester.pumpAndSettle();
      final result = tester.widget<ResultScreen>(find.byType(ResultScreen));
      expect(result.moews!.riskLevel, 'UNKNOWN');
    });

    testWidgets('typed values are scored', (tester) async {
      await open(tester);
      await fillVitals(tester, overrides: {'sbp': '70'});
      await tester.tap(find.text('Continue to Result'));
      await tester.pumpAndSettle();
      final result = tester.widget<ResultScreen>(find.byType(ResultScreen));
      expect(result.moews!.riskLevel, 'RED');
      expect(result.vitals!['systolic_bp'], 70);
    });

    testWidgets('ticking not measured clears a typed value', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('vitals_sbp')), '120');
      await tester.tap(find.byKey(const Key('vitals_sbp_not_measured')));
      await tester.pump();
      expect(_text(tester, 'vitals_sbp'), isEmpty);
    });
  });

  group('ReferralScreen', () {
    Future<void> open(
      WidgetTester tester, {
      Map<String, Object?>? vitals,
    }) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(home: ReferralScreen(initialVitals: vitals)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('name and every vital start empty', (tester) async {
      await open(tester);
      expect(find.text('Ama Mensah'), findsNothing);
      for (final id in _ids) {
        expect(_text(tester, 'referral_$id'), isEmpty, reason: id);
      }
      expect(find.text('V — Voice'), findsNothing);
      for (final fake in ['70', '50', '140', '35', '39.5', '85']) {
        expect(find.text(fake), findsNothing, reason: fake);
      }
    });

    testWidgets('untouched form asks for each answer', (tester) async {
      await open(tester);
      // Facility confirmation is checked after validation.
      await tester.tap(find.text('Confirm Referral'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the name, or type Unknown'), findsOneWidget);
      expect(find.text('Enter a value or tick Not measured'), findsNWidgets(6));
      expect(find.text('Select AVPU or Not measured'), findsOneWidget);
    });

    testWidgets('not measured carries over from the vitals step',
        (tester) async {
      await open(
        tester,
        vitals: const {
          'systolic_bp': null,
          'diastolic_bp': 80,
          'consciousness_level': null,
        },
      );
      expect(_text(tester, 'referral_sbp'), isEmpty);
      final sbpBox = tester.widget<Checkbox>(
        find.descendant(
          of: find.byKey(const Key('referral_sbp_not_measured')),
          matching: find.byType(Checkbox),
        ),
      );
      expect(sbpBox.value, isTrue);
      expect(_text(tester, 'referral_dbp'), '80');
      expect(find.text('Not measured').evaluate().length, greaterThan(6));
    });
  });

  group('limits', _limitTests);

  group('calculateMoews', () {
    test('null consciousness is UNKNOWN', () {
      final r = calculateMoews(
        sbp: 120,
        dbp: 80,
        hr: 80,
        rr: 18,
        temp: 37.0,
        spo2: 98,
        consciousness: null,
      );
      expect(r.riskLevel, 'UNKNOWN');
      expect(r.score, isNull);
    });
  });
}

void _limitTests() {
  testWidgets('out-of-range values cannot be submitted', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(home: VitalsScreen(result: moewsOnlyResult())),
    );
    await fillVitals(tester, overrides: {'sbp': '1200'});
    await tester.tap(find.text('Continue to Result'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultScreen), findsNothing);
    expect(find.text('Check this value: must be 0 to 300'), findsOneWidget);
  });

  test('limits accept the bounds and reject just outside them', () {
    const limits = VitalLimits.temperature;
    expect(limits.errorFor(20), isNull);
    expect(limits.errorFor(45), isNull);
    expect(limits.errorFor(19.9), isNotNull);
    expect(limits.errorFor(45.1), isNotNull);
  });
}
