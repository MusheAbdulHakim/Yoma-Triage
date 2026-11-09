import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/services/screening_service.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

import 'helpers/cho_helper.dart';

/// A breathing check that records nothing and whose analysis never ends, and says when it
/// was stopped or cancelled.
class _Recorder extends ScreeningService {
  bool disposed = false;
  bool cancelled = false;

  @override
  Future<void> startRecording() async {}

  @override
  Stream<double> microphoneLevels() => const Stream.empty();

  @override
  Future<ScreeningResult> stopAndClassify() => Completer<ScreeningResult>().future;

  @override
  void cancelAnalysis() => cancelled = true;

  @override
  Future<void> dispose() async => disposed = true;
}

/// A page that opens [screen], as Home does.
Future<void> _openFromPage(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildYomaTheme(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tapBackArrow(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(registeredChoPrefs()));

  final vitals = {
    'systolic_bp': 120,
    'diastolic_bp': 80,
    'heart_rate': 80,
    'respiratory_rate': 18,
    'temperature': 37.0,
    'spo2': 98,
    'consciousness_level': 'A',
  };

  for (final (name, screen) in <(String, Widget)>[
    ('Record vitals', VitalsScreen(result: moewsOnlyResult())),
    (
      'Result',
      ResultScreen(
        result: moewsOnlyResult(),
        vitals: vitals,
        moews: calculateMoews(
            sbp: 120, dbp: 80, hr: 80, rr: 18, temp: 37.0, spo2: 98, consciousness: 'A'),
      ),
    ),
    ('Emergency referral form', const ReferralScreen()),
    (
      'Breathing check (Ready)',
      ScreeningScreen(forceWebSimulator: false, service: _Recorder(), showReadyStep: true),
    ),
  ]) {
    testWidgets('$name: a visible back arrow in the top bar that goes back', (tester) async {
      await _openFromPage(tester, screen);
      final arrow = find.descendant(of: find.byType(AppBar), matching: find.byType(BackButton));
      expect(arrow.hitTestable(), findsOneWidget);
      await _tapBackArrow(tester);
      expect(find.text('open'), findsOneWidget, reason: 'back on the page it came from');
    });
  }

  testWidgets('Breathing check: the arrow while recording leaves and stops the recorder',
      (tester) async {
    final recorder = _Recorder();
    await _openFromPage(
        tester, ScreeningScreen(forceWebSimulator: false, service: recorder, showReadyStep: false));
    expect(find.byKey(const Key('screening_stop')), findsOneWidget, reason: 'recording');
    expect(find.byType(BackButton).hitTestable(), findsOneWidget);
    await _tapBackArrow(tester);
    expect(find.text('open'), findsOneWidget);
    expect(recorder.disposed, isTrue, reason: 'leaving mid-recording stops the recorder');
  });

  testWidgets('Breathing check: the arrow while analysing leaves and cancels the analysis',
      (tester) async {
    final recorder = _Recorder();
    await _openFromPage(
        tester, ScreeningScreen(forceWebSimulator: false, service: recorder, showReadyStep: false));
    await tester.tap(find.byKey(const Key('screening_stop')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Checking the recording…'), findsOneWidget);
    expect(find.byType(BackButton).hitTestable(), findsOneWidget);
    await _tapBackArrow(tester);
    expect(find.text('open'), findsOneWidget);
    expect(recorder.cancelled, isTrue, reason: 'leaving mid-analysis cancels it');
  });
}
