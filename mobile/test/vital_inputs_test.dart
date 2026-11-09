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
import 'helpers/cho_helper.dart';

const _ids = ['sbp', 'dbp', 'hr', 'rr', 'temp', 'spo2'];

String _text(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

/// The "Not measured" toggles: blood pressure has one for both fields.
const _toggleIds = ['bp', 'hr', 'rr', 'temp', 'spo2'];

Future<void> _tickAllNotMeasured(WidgetTester tester, String prefix) async {
  for (final id in _toggleIds) {
    await tester.tap(find.byKey(Key('${prefix}_${id}_not_measured')));
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(registeredChoPrefs()));

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
      expectNoAvpuSelected(tester, 'vitals');
    });

    testWidgets('untouched form cannot continue', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('vitals_see_result')));
      await tester.pumpAndSettle();
      expect(find.byType(ResultScreen), findsNothing);
      // Each required vital shows its own message, whole, below its field; blood pressure
      // says it once for both halves, and Oxygen saturation (optional) says nothing.
      for (final id in ['hr', 'rr', 'temp']) {
        final shown = tester.widget<Text>(find.byKey(Key('vitals_${id}_error')));
        expect(shown.data, 'Enter a value or tick Not measured', reason: id);
      }
      expect(tester.widget<Text>(find.byKey(const Key('vitals_sbp_error'))).data,
          'Enter both values or tick Not measured');
      expect(find.byKey(const Key('vitals_dbp_error')), findsNothing);
      expect(find.byKey(const Key('vitals_spo2_error')), findsNothing);
      expect(find.text('Select AVPU or Not measured'), findsOneWidget);
    });

    testWidgets('all not measured says Incomplete and lists what is missing', (tester) async {
      await open(tester);
      await _tickAllNotMeasured(tester, 'vitals');
      await selectAvpu(tester, avpu: 'Not measured');

      await tester.tap(find.byKey(const Key('vitals_see_result')));
      await tester.pumpAndSettle();

      final result = tester.widget<ResultScreen>(find.byType(ResultScreen));
      expect(result.moews!.riskLevel, 'INCOMPLETE');
      expect(result.vitals!['systolic_bp'], isNull);
      expect(result.vitals!['consciousness_level'], isNull);
      expect(result.vitals!.containsKey('systolic_bp'), isTrue);
      expect(find.text('Incomplete'), findsOneWidget);
      expect(find.textContaining('GREEN'), findsNothing);
      // Listed one per row under "Not measured", every vital named.
      final missing = find.byKey(const Key('moews_not_measured'));
      expect(missing, findsOneWidget);
      expect(find.descendant(of: missing, matching: find.text('Not measured')), findsOneWidget);
      for (final name in const [
        'Systolic BP',
        'Diastolic BP',
        'Heart rate',
        'Breathing rate',
        'Temperature',
        'Oxygen saturation',
        'Consciousness',
      ]) {
        expect(find.descendant(of: missing, matching: find.text(name)), findsOneWidget,
            reason: name);
      }
      expect(find.text('Confirm Referral'), findsOneWidget);
      expect(find.text('Continue Monitoring'), findsOneWidget);
    });

    testWidgets('AVPU not measured alone is Incomplete, not Alert',
        (tester) async {
      await open(tester);
      await fillVitals(tester, avpu: 'Not measured');
      await tester.tap(find.byKey(const Key('vitals_see_result')));
      await tester.pumpAndSettle();
      final result = tester.widget<ResultScreen>(find.byType(ResultScreen));
      expect(result.moews!.riskLevel, 'INCOMPLETE');
      final missing = find.byKey(const Key('moews_not_measured'));
      expect(find.descendant(of: missing, matching: find.text('Consciousness')), findsOneWidget);
      expect(find.descendant(of: missing, matching: find.text('Heart rate')), findsNothing);
    });

    testWidgets('measured critical value is RED even with vitals missing',
        (tester) async {
      await open(tester);
      await fillVitals(tester, overrides: {'sbp': '60'});
      await tester.tap(find.byKey(const Key('vitals_temp_not_measured')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('vitals_see_result')));
      await tester.pumpAndSettle();
      expect(find.text('MOEWS RED'), findsOneWidget);
      expect(find.text('Not measured: Temperature'), findsOneWidget);
      expect(find.textContaining('from measured vitals'), findsOneWidget);
      expect(find.text('Confirm Referral'), findsOneWidget);
    });

    testWidgets('GREEN without SpO₂ says so', (tester) async {
      await open(tester);
      await fillVitals(tester);
      await tester.tap(find.byKey(const Key('vitals_spo2_not_measured')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('vitals_see_result')));
      await tester.pumpAndSettle();
      expect(find.text('MOEWS GREEN'), findsOneWidget);
      expect(find.text('Oxygen saturation not measured'), findsOneWidget);
    });

    testWidgets('GREEN with a full set shows no missing note', (tester) async {
      await open(tester);
      await fillVitals(tester);
      await tester.tap(find.byKey(const Key('vitals_see_result')));
      await tester.pumpAndSettle();
      expect(find.text('MOEWS GREEN'), findsOneWidget);
      expect(find.byKey(const Key('moews_not_measured')), findsNothing);
    });

    testWidgets('typed values are scored', (tester) async {
      await open(tester);
      await fillVitals(tester, overrides: {'sbp': '70'});
      await tester.tap(find.byKey(const Key('vitals_see_result')));
      await tester.pumpAndSettle();
      final result = tester.widget<ResultScreen>(find.byType(ResultScreen));
      expect(result.moews!.riskLevel, 'RED');
      expect(result.vitals!['systolic_bp'], 70);
    });

    testWidgets('ticking not measured clears a typed value', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('vitals_sbp')), '120');
      await tester.enterText(find.byKey(const Key('vitals_dbp')), '80');
      await tester.tap(find.byKey(const Key('vitals_bp_not_measured')));
      await tester.pump();
      expect(_text(tester, 'vitals_sbp'), isEmpty);
      expect(_text(tester, 'vitals_dbp'), isEmpty, reason: 'one toggle covers both');
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

    testWidgets('no name field and no vital fields: one summary row, not recorded',
        (tester) async {
      await open(tester);
      expect(find.byType(TextField), findsNothing, reason: 'vitals are entered in one place');
      expect(find.text('Not recorded'), findsOneWidget);
      for (final fake in ['70', '50', '140', '35', '39.5', '85']) {
        expect(find.text(fake), findsNothing, reason: fake);
      }
    });

    testWidgets('untouched form asks for vitals before it sends', (tester) async {
      await open(tester);
      // Send stays disabled until a type is chosen, and says so.
      final send = find.byKey(const Key('referral_send'));
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(find.byKey(const Key('referral_send_hint')), findsOneWidget);
      await tester.tap(find.byKey(const Key('referral_type_pph')));
      await tester.pump();
      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
      // Facility confirmation is checked after the type (once the catalog has loaded,
      // which only advances in real time here).
      await tester.tap(send);
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (find.textContaining('Choose receiving facility').evaluate().isNotEmpty) break;
      }
      expect(find.textContaining('Choose receiving facility'), findsOneWidget);
    });

    testWidgets('the summary opens Record vitals with the values carried over',
        (tester) async {
      await open(
        tester,
        vitals: const {
          'systolic_bp': null,
          'diastolic_bp': null,
          'heart_rate': 80,
          'respiratory_rate': 18,
          'temperature': 37.0,
          'spo2': 98,
          'consciousness_level': null,
        },
      );
      expect(find.text('Incomplete'), findsOneWidget);
      await tester.tap(find.byKey(const Key('referral_vitals_summary')));
      await tester.pumpAndSettle();
      // Not measured stays not measured; values stay values.
      expect(_text(tester, 'vitals_sbp'), isEmpty);
      expect(markedNotMeasured('vitals_bp_not_measured'), isTrue);
      expect(_text(tester, 'vitals_hr'), '80');
      expect(markedNotMeasured('vitals_avpu_not_measured'), isTrue);

      // Saving hands the vitals back to the form, which scores them.
      await tester.tap(find.byKey(const Key('vitals_bp_not_measured')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('vitals_sbp')), '185');
      await tester.enterText(find.byKey(const Key('vitals_dbp')), '80');
      await selectAvpu(tester, avpu: 'A — Alert');
      await tester.tap(find.byKey(const Key('vitals_see_result')));
      await tester.pumpAndSettle();
      expect(find.byType(ReferralScreen), findsOneWidget);
      expect(find.text('Critical (Score 3)'), findsOneWidget);
    });
  });

  group('limits', _limitTests);

  group('calculateMoews', () {
    test('null consciousness is INCOMPLETE', () {
      final r = calculateMoews(
        sbp: 120,
        dbp: 80,
        hr: 80,
        rr: 18,
        temp: 37.0,
        spo2: 98,
        consciousness: null,
      );
      expect(r.riskLevel, 'INCOMPLETE');
      expect(r.missingVitals, ['consciousness_level']);
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
    await tester.tap(find.byKey(const Key('vitals_see_result')));
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
