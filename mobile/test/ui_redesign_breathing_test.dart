// UI redesign round 2: the breathing check flow. The classification, thresholds and
// flow are unchanged; these tests pin what the new screens may and may not do.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/config.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/services/screening_service.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';
import 'package:yoma_triage/widgets/breathing_check.dart';

import 'helpers/cho_helper.dart';

/// A recorder-free service: the test feeds microphone levels and picks the result.
class _FakeService extends ScreeningService {
  _FakeService({this.result, this.failStart});

  final ScreeningResult? result;
  final Object? failStart;
  final levels = StreamController<double>.broadcast();
  int classified = 0;
  bool cancelled = false;
  final _analysis = Completer<ScreeningResult>();

  @override
  Future<void> startRecording() async {
    if (failStart != null) throw failStart!;
  }

  @override
  Stream<double> microphoneLevels() => levels.stream;

  @override
  Future<ScreeningResult> stopAndClassify() {
    classified++;
    if (result != null) return Future.value(result);
    return _analysis.future; // Waits until cancelled.
  }

  @override
  void cancelAnalysis() {
    cancelled = true;
    if (!_analysis.isCompleted) _analysis.complete(cancelledResult());
  }

  @override
  Future<void> dispose() async {}
}

ScreeningResult _acoustic(String label) => ScreeningResult(
      label: label,
      confidence: 0.7,
      reason: 'test',
      source: 'yamnet',
      modelVersion: 'test',
    );

Future<void> _open(
  WidgetTester tester,
  ScreeningService service, {
  bool ready = false,
  bool resultStep = false,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildYomaTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: ScreeningScreen(
      forceWebSimulator: false,
      service: service,
      showReadyStep: ready,
      showResultStep: resultStep,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Pumps fake time while the pulse repeats (pumpAndSettle would never settle).
Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final steps = d.inMilliseconds ~/ 100;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

ApiClient _offline() => ApiClient(
      client: MockClient((_) async => throw http.ClientException('no signal')),
      baseUrl: 'http://test.invalid',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(registeredChoPrefs()));

  group('only in acoustic mode', () {
    testWidgets('MOEWS-only Home has no way into the breathing check', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(acousticEnabled: false, api: _offline()),
      ));
      await tester.pump();
      expect(find.byKey(const Key('home_check_breathing')), findsNothing);
      expect(find.byType(ScreeningScreen), findsNothing);
    });

    testWidgets('acoustic Home opens it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(acousticEnabled: true, api: _offline()),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_check_breathing')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ScreeningScreen), findsOneWidget);
    });

    test('the default build is MOEWS-only', () {
      const defined = String.fromEnvironment('MOEWS_ONLY');
      if (defined.isEmpty) expect(ScreeningConfig.moewsOnly, isTrue);
    });
  });

  group('result is never normal', () {
    test('only an acoustic RED raises a concern; everything else is "Couldn\'t tell"', () {
      expect(BreathingVariant.of(_acoustic('RED')), BreathingVariant.possibleProblem);
      for (final label in ['GREEN', 'INCONCLUSIVE', 'YELLOW']) {
        expect(BreathingVariant.of(_acoustic(label)), BreathingVariant.couldntTell, reason: label);
      }
      expect(BreathingVariant.of(cancelledResult()), BreathingVariant.couldntTell);
      expect(BreathingVariant.of(unavailableResult()), BreathingVariant.couldntTell);
      for (final v in BreathingVariant.values) {
        expect('${v.title} ${v.line}'.toLowerCase(), isNot(contains('normal')));
      }
    });

    testWidgets('a GREEN from the classifier shows "Couldn\'t tell", no green, no "normal"',
        (tester) async {
      final service = _FakeService(result: _acoustic('GREEN'));
      await _open(tester, service, resultStep: true);
      await tester.tap(find.byKey(const Key('screening_stop')));
      await _pumpFor(tester, const Duration(milliseconds: 500));

      expect(find.byKey(const Key('breathing_result_couldntTell')), findsOneWidget);
      expect(find.text("Couldn't tell"), findsOneWidget);
      expect(find.textContaining('GREEN'), findsNothing);
      expect(find.textContaining(RegExp('normal', caseSensitive: false)), findsNothing);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(
          [TriageColors.red, TriageColors.amber, TriageColors.green].contains(text.style?.color),
          isFalse,
          reason: text.data,
        );
      }

      // Continue to vitals carries the classifier's own result, unchanged.
      await tester.tap(find.byKey(const Key('screening_continue_to_vitals')));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(tester.widget<VitalsScreen>(find.byType(VitalsScreen)).result.label, 'GREEN');
    });

    testWidgets('a RED shows "Possible breathing problem" with the Advisory tag',
        (tester) async {
      await _open(tester, _FakeService(result: _acoustic('RED')), resultStep: true);
      await tester.tap(find.byKey(const Key('screening_stop')));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.byKey(const Key('breathing_result_possibleProblem')), findsOneWidget);
      expect(find.text('Advisory'), findsOneWidget);
    });

    testWidgets('without the result step (today\'s flow) it goes straight to vitals',
        (tester) async {
      await _open(tester, _FakeService(result: _acoustic('RED')));
      await tester.tap(find.byKey(const Key('screening_stop')));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.byType(VitalsScreen), findsOneWidget);
    });
  });

  group('INCONCLUSIVE paths', () {
    testWidgets('Cancel during analysis gives INCONCLUSIVE and goes on to vitals',
        (tester) async {
      final service = _FakeService(); // Analysis waits until cancelled.
      await _open(tester, service);
      await tester.tap(find.byKey(const Key('screening_stop')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Checking the recording…'), findsOneWidget);
      expect(find.byKey(const Key('screening_progress')), findsOneWidget);

      await tester.tap(find.byKey(const Key('screening_cancel')));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(service.cancelled, isTrue);
      final result = tester.widget<VitalsScreen>(find.byType(VitalsScreen)).result;
      expect(result.label, 'INCONCLUSIVE');
      expect(result.source, 'cancelled');
    });

    testWidgets('microphone denied: Open settings and Skip to vitals; skip is INCONCLUSIVE',
        (tester) async {
      final service = _FakeService(failStart: StateError('Microphone permission denied'));
      await _open(tester, service, resultStep: true);
      expect(find.text('Microphone not allowed'), findsOneWidget);
      expect(find.byKey(const Key('screening_open_settings')), findsOneWidget);

      // Open settings goes to the platform; it never ends the check by itself.
      await tester.tap(find.byKey(const Key('screening_open_settings')));
      await tester.pump();
      expect(find.byType(VitalsScreen), findsNothing);

      await tester.tap(find.byKey(const Key('screening_skip_to_vitals')));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      // Straight to vitals, even with the result step on, as the denied path does today.
      final result = tester.widget<VitalsScreen>(find.byType(VitalsScreen)).result;
      expect(result.label, 'INCONCLUSIVE');
      expect(result.source, 'unavailable');
      expect(service.classified, 0, reason: 'nothing was recorded, nothing classified');
    });
  });

  group('recording', () {
    testWidgets('the countdown and the Ready text use the configured length', (tester) async {
      final seconds = ScreeningConfig.durationSec;
      await _open(tester, _FakeService(result: _acoustic('INCONCLUSIVE')), ready: true);
      expect(find.text('Keep the phone still for $seconds seconds'), findsOneWidget);
      expect(find.byKey(const Key('breathing_pulse')), findsNothing, reason: 'not recording yet');

      await tester.tap(find.byKey(const Key('screening_start')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('$seconds s'), findsOneWidget);
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('${seconds - 2} s'), findsOneWidget);
    });

    testWidgets('pulse rings animate; with Remove animations on, a static ring', (tester) async {
      await _open(tester, _FakeService(result: _acoustic('INCONCLUSIVE')));
      expect(find.byKey(const Key('breathing_pulse_rings')), findsOneWidget);
      expect(find.byKey(const Key('breathing_pulse_static')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _open(tester, _FakeService(result: _acoustic('INCONCLUSIVE')), reduceMotion: true);
      expect(find.byKey(const Key('breathing_pulse_static')), findsOneWidget);
      expect(find.byKey(const Key('breathing_pulse_rings')), findsNothing);
    });

    testWidgets('near-silence for 3 s shows the hint, and the classification is untouched',
        (tester) async {
      final service = _FakeService(result: _acoustic('RED'));
      await _open(tester, service);
      const hint = Key('screening_silence_hint');

      // Loud enough: no hint.
      for (var i = 0; i < 20; i++) {
        service.levels.add(0.6);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(hint), findsNothing);

      // 2 s of near-silence: not yet.
      for (var i = 0; i < 20; i++) {
        service.levels.add(0.02);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(hint), findsNothing);

      // Past 3 s: the hint.
      for (var i = 0; i < 15; i++) {
        service.levels.add(0.02);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(hint), findsOneWidget);
      expect(find.text(silenceHintText), findsOneWidget);

      // Sound again: it goes away.
      service.levels.add(0.6);
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.byKey(hint), findsNothing);

      // Stopping classifies once, and the result is the classifier's own.
      await tester.tap(find.byKey(const Key('screening_stop')));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(service.classified, 1);
      expect(tester.widget<VitalsScreen>(find.byType(VitalsScreen)).result.label, 'RED');
    });

    testWidgets('no level readings at all (unsupported): no hint, never a false alarm',
        (tester) async {
      await _open(tester, _FakeService(result: _acoustic('INCONCLUSIVE')));
      await _pumpFor(tester, const Duration(seconds: 5));
      expect(find.byKey(const Key('screening_silence_hint')), findsNothing);
    });

    testWidgets('screen reader: countdown every 5 s (not every second), and the hint',
        (tester) async {
      final announced = <String>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        (message) async {
          final data = (message as Map)['data'] as Map?;
          if (message['type'] == 'announce') announced.add(data!['message'] as String);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, null));

      final service = _FakeService(result: _acoustic('INCONCLUSIVE'));
      final seconds = ScreeningConfig.durationSec;
      await _open(tester, service);
      for (var i = 0; i < 40; i++) {
        service.levels.add(0.0);
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(announced.first, contains('$seconds seconds'));
      final countdown = announced.where((m) => m.endsWith('seconds left')).toList();
      // 4 s in: only the multiple of 5 passed so far is announced.
      for (final m in countdown) {
        final n = int.parse(m.split(' ').first);
        expect(n % 5, 0, reason: m);
      }
      expect(countdown.length, lessThanOrEqualTo(1));
      expect(announced, contains(silenceHintText));
    });
  });
}
