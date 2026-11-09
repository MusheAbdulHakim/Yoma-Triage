/// UI redesign round 2, on a device (acoustic build, MOEWS_ONLY=false):
///
/// 1. The real breathing check — real recorder, real amplitude polling, the pulse
///    animating, then the real analysis — while a 10 ms timer on the main isolate measures
///    the longest time the thread could do nothing else (as in s10), and frame timings
///    count frames over budget. Recording and analysis are measured separately.
/// 2. Screenshots of every breathing screen. A scripted service supplies the microphone
///    level, so the quiet and loud pulse sizes and the silence hint are repeatable.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yoma_triage/config.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/services/screening_service.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

import 'support/harness.dart';

/// Records nothing; the test sets the level and the result.
class _Scripted extends ScreeningService {
  _Scripted({this.result, this.failStart, this.level});

  final ScreeningResult? result;
  final Object? failStart;
  final double? level;
  final _analysis = Completer<ScreeningResult>();
  Timer? _feed;
  final _levels = StreamController<double>.broadcast();

  @override
  Future<void> startRecording() async {
    if (failStart != null) throw failStart!;
    if (level != null) {
      _feed = Timer.periodic(const Duration(milliseconds: 120), (_) => _levels.add(level!));
    }
  }

  @override
  Stream<double> microphoneLevels() => _levels.stream;

  @override
  Future<ScreeningResult> stopAndClassify() {
    _feed?.cancel();
    return result != null ? Future.value(result) : _analysis.future;
  }

  @override
  void cancelAnalysis() {
    if (!_analysis.isCompleted) _analysis.complete(cancelledResult());
  }

  @override
  Future<void> dispose() async => _feed?.cancel();
}

ScreeningResult _acoustic(String label) => ScreeningResult(
      label: label,
      confidence: 0.7,
      reason: 'scripted',
      source: 'yamnet',
      modelVersion: 'scripted',
    );

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('Breathing check: stalls during the real recording and analysis, and screenshots',
      (tester) async {
    expect(ScreeningConfig.moewsOnly, isFalse, reason: 'run with MOEWS_ONLY=false');
    await tester.setUpCho();
    await Host.grantMicrophone();
    await tester.wait(const Duration(seconds: 2));

    Future<void> show(Widget screen, {bool reduceMotion = false}) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(MaterialApp(
        theme: buildYomaTheme(),
        debugShowCheckedModeBanner: false,
        // The harness turns device animations off for stable runs; the pulse is shown as
        // a CHO with animations on would see it, unless this shot is the reduced-motion one.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: screen,
      ));
    }

    // ---- 1. Measured, with no screenshots inside any measured window. ----
    // A: control, the recording screen with the static ring (scripted level).
    // B: the same with the pulse animating, so B - A is the pulse's own cost.
    // C: the real thing: recorder, amplitude polling, pulse, then the real analysis.
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final clock = Stopwatch()..start();
    var lastTick = clock.elapsedMilliseconds;
    var phase = 'idle';
    final longest = <String, int>{};
    final frames = <String, List<FrameTiming>>{};
    final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final now = clock.elapsedMilliseconds;
      if (phase != 'idle') longest[phase] = max(longest[phase] ?? 0, now - lastTick);
      lastTick = now;
    });
    addTearDown(ticker.cancel);
    void onFrames(List<FrameTiming> timings) {
      if (phase != 'idle') (frames[phase] ??= []).addAll(timings);
    }

    SchedulerBinding.instance.addTimingsCallback(onFrames);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(onFrames));

    Future<void> measure(String name, Duration d) async {
      phase = name;
      lastTick = clock.elapsedMilliseconds;
      await tester.wait(d);
      phase = 'idle';
    }

    await show(ScreeningScreen(service: _Scripted(level: 0.5)), reduceMotion: true);
    await tester.wait(const Duration(seconds: 1));
    await measure('control_static_ring', const Duration(seconds: 8));
    await show(ScreeningScreen(service: _Scripted(level: 0.5)));
    await tester.wait(const Duration(seconds: 1));
    await measure('pulse_scripted', const Duration(seconds: 8));

    await show(const ScreeningScreen());
    phase = 'recording';
    lastTick = clock.elapsedMilliseconds;
    await tester.waitFor(find.text('Checking the recording…'),
        timeout: Duration(seconds: ScreeningConfig.durationSec + 15));
    phase = 'analysis';
    lastTick = clock.elapsedMilliseconds;
    await tester.waitFor(find.byType(VitalsScreen), timeout: const Duration(seconds: 60));
    phase = 'idle';

    String frameSummary(List<FrameTiming>? list) {
      if (list == null || list.isEmpty) return 'no frames';
      final totals = list.map((t) => t.totalSpan.inMicroseconds / 1000).toList()..sort();
      final over = totals.where((ms) => ms > 1000 / 60).length;
      return '${list.length} frames, $over over 16.7 ms '
          '(${(100 * over / list.length).toStringAsFixed(0)}%), '
          'median ${totals[totals.length ~/ 2].toStringAsFixed(1)} ms, '
          '95th ${totals[(totals.length * 0.95).floor()].toStringAsFixed(1)} ms, '
          'worst ${totals.last.toStringAsFixed(1)} ms';
    }

    for (final name in ['control_static_ring', 'pulse_scripted', 'recording', 'analysis']) {
      await Host.metric('breathing_${name}_longest_block_ms', longest[name] ?? -1);
      await Host.note('Breathing $name: main thread longest block ${longest[name]} ms; '
          '${frameSummary(frames[name])}.');
    }
    expect(longest['recording']!, lessThan(1000));
    expect(longest['analysis']!, lessThan(1000));
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fadePointers;

    // The real microphone, for the record: on the emulator the input is near silent, so
    // with amplitude readings arriving the hint should show.
    await show(const ScreeningScreen());
    await tester.wait(const Duration(seconds: 5));
    await Host.note('Silence hint with the emulator microphone after 5 s: '
        '${find.byKey(const Key('screening_silence_hint')).evaluate().isNotEmpty}.');
    await tester.shot('b_recording_live');
    // A moment later: the rings move with the sound.
    await tester.wait(const Duration(milliseconds: 700));
    await tester.shot('b_recording_live_2');
    await tester.tapOn(find.byKey(const Key('screening_stop')));
    await tester.waitFor(find.byType(VitalsScreen), timeout: const Duration(seconds: 60));

    // ---- 2. Every screen, scripted. ----
    await show(ScreeningScreen(
        service: _Scripted(level: 0.1), showReadyStep: true, showResultStep: true));
    await tester.wait(const Duration(seconds: 1));
    await tester.shot('b_1_ready');

    await show(ScreeningScreen(service: _Scripted(level: 0.12)));
    await tester.wait(const Duration(milliseconds: 2500));
    await tester.shot('b_2_recording_quiet');

    await show(ScreeningScreen(service: _Scripted(level: 0.95)));
    await tester.wait(const Duration(milliseconds: 2500));
    await tester.shot('b_3_recording_loud');

    await show(ScreeningScreen(service: _Scripted(level: 0.0)));
    await tester.wait(const Duration(seconds: 4));
    expect(find.byKey(const Key('screening_silence_hint')), findsOneWidget);
    await tester.shot('b_4_recording_silence_hint');

    await show(ScreeningScreen(service: _Scripted(level: 0.6)), reduceMotion: true);
    await tester.wait(const Duration(seconds: 2));
    expect(find.byKey(const Key('breathing_pulse_static')), findsOneWidget);
    await tester.shot('b_5_recording_reduced_motion');

    final analysing = _Scripted(level: 0.5);
    await show(ScreeningScreen(service: analysing));
    await tester.wait(const Duration(seconds: 1));
    await tester.tapOn(find.byKey(const Key('screening_stop')));
    await tester.wait(const Duration(seconds: 1));
    await tester.shot('b_6_analysing');
    analysing.cancelAnalysis();
    await tester.waitFor(find.byType(VitalsScreen));

    for (final (label, name) in [('RED', 'possible_problem'), ('INCONCLUSIVE', 'couldnt_tell')]) {
      await show(ScreeningScreen(
          service: _Scripted(result: _acoustic(label), level: 0.5), showResultStep: true));
      await tester.wait(const Duration(seconds: 1));
      await tester.tapOn(find.byKey(const Key('screening_stop')));
      await tester.waitFor(find.byKey(const Key('screening_continue_to_vitals')));
      await tester.shot('b_7_result_$name');
    }

    await show(ScreeningScreen(
        service: _Scripted(failStart: StateError('Microphone permission denied'))));
    await tester.wait(const Duration(seconds: 1));
    await tester.shot('b_8_microphone_blocked');

    final vitals = {
      'systolic_bp': 120,
      'diastolic_bp': 80,
      'heart_rate': 118,
      'respiratory_rate': 18,
      'temperature': 37.0,
      'spo2': 98,
      'consciousness_level': 'A',
    };
    await show(ResultScreen(
      result: _acoustic('RED'),
      vitals: vitals,
      moews: calculateMoews(
          sbp: 120, dbp: 80, hr: 118, rr: 18, temp: 37.0, spo2: 98, consciousness: 'A'),
    ));
    await tester.wait(const Duration(seconds: 1));
    await tester.shot('b_9_result_advisory_row');
  });
}
