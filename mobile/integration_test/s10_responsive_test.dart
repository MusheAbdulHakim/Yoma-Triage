/// A1: breath screening must never freeze the app. While YAMNet analyses a full-length
/// capture, the screen has to keep drawing frames and answering taps.
///
/// Main-thread blocking is measured with a 10 ms timer on the main isolate: the longest gap
/// between two ticks is the longest time the thread could do nothing else.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yoma_triage/config.dart';
import 'package:yoma_triage/services/yamnet_classifier.dart';

import 'support/harness.dart';

const _sampleRate = 16000;

Uint8List _tone(int seconds) {
  final bytes = ByteData(_sampleRate * seconds * 2);
  for (var i = 0; i < _sampleRate * seconds; i++) {
    final sample = (sin(2 * pi * 440 * i / _sampleRate) * 0.5 * 32767).round();
    bytes.setInt16(i * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the screen keeps drawing and answering taps while YAMNet runs', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

    final classifier = await createYamnetClassifier();
    addTearDown(classifier.dispose);
    final capture = _tone(ScreeningConfig.durationSec);

    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: () => taps++, child: const Text('Tap me')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    var running = false;
    var frames = 0;
    void countFrames(List<FrameTiming> timings) {
      if (running) frames += timings.length;
    }

    SchedulerBinding.instance.addTimingsCallback(countFrames);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(countFrames));

    final clock = Stopwatch()..start();
    var lastTick = clock.elapsedMilliseconds;
    var longestBlock = 0;
    final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final now = clock.elapsedMilliseconds;
      longestBlock = max(longestBlock, now - lastTick);
      lastTick = now;
    });
    addTearDown(ticker.cancel);

    running = true;
    final started = clock.elapsedMilliseconds;
    var finishedAt = -1;
    final analysis = classifier.classifyPcm16kHzMono(capture).then((result) {
      finishedAt = clock.elapsedMilliseconds;
      return result;
    });

    // A CHO's tap, a second into the analysis.
    await tester.pump(const Duration(seconds: 1));
    final tapStillRunning = finishedAt < 0;
    await tester.tap(find.text('Tap me'));
    await tester.pump(const Duration(milliseconds: 100));
    final tapHandledWhileRunning = tapStillRunning && taps == 1;

    final result = await analysis;
    running = false;
    // One more tick after the analysis, so a block that ran to the end is counted.
    await tester.pump(const Duration(milliseconds: 50));
    ticker.cancel();

    final inferenceMs = finishedAt - started;
    final framesPerSecond = inferenceMs > 0 ? frames * 1000 / inferenceMs : 0;
    await Host.metric('responsive_inference_ms', inferenceMs);
    await Host.metric('responsive_main_thread_longest_block_ms', longestBlock);
    await Host.metric('responsive_frames_during_inference', frames);
    await Host.note(
      'Full ${ScreeningConfig.durationSec} s capture: ${result.label} from ${result.source} in '
      '$inferenceMs ms. Main thread longest block $longestBlock ms. '
      '$frames frames drawn during analysis (${framesPerSecond.toStringAsFixed(1)} per second). '
      'Tap a second in handled while analysis still running: $tapHandledWhileRunning.',
    );

    expect(result.source, 'yamnet', reason: 'the real model must run: ${result.reason}');
    expect(tapHandledWhileRunning, isTrue, reason: 'a tap during analysis must be handled');
    expect(longestBlock, lessThan(500), reason: 'the main thread must never stall for long');
    expect(framesPerSecond, greaterThan(10), reason: 'the screen must keep drawing');
  });
}
