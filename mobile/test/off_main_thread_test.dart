// A1: screening must never freeze the app. Inference runs in a background isolate that
// Cancel can stop, and the screen shows progress and a Cancel button while it runs.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/config.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/audio_recorder_base.dart';
import 'package:yoma_triage/services/background_job.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/services/screening_service.dart';
import 'package:yoma_triage/services/yamnet_classifier_base.dart';
import 'package:yoma_triage/services/yamnet_classifier_io.dart';

/// Busy work that never yields, as model inference doesn't.
int _spin(int milliseconds) {
  final watch = Stopwatch()..start();
  var count = 0;
  while (watch.elapsedMilliseconds < milliseconds) {
    count++;
  }
  return count;
}

Uint8List _pcm(int samples, {double value = 0.25}) {
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, (value * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// A classifier that finishes only when told, and records a cancel.
class _SlowClassifier implements YamnetClassifier {
  final finish = Completer<ScreeningResult>();
  var cancelled = false;

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) => finish.future;

  @override
  void cancel() {
    cancelled = true;
    if (!finish.isCompleted) finish.complete(cancelledResult());
  }

  @override
  Future<void> dispose() async {}
}

class _FakeRecorder implements AudioRecorderService {
  @override
  Future<void> start() async {}

  @override
  Future<Uint8List> stop() async => _pcm(16000);

  @override
  Future<void> dispose() async {}
}

/// Records and analyses for the screen without a microphone. The analysis waits for
/// [_SlowClassifier], whatever MOEWS_ONLY says.
class _SlowService extends ScreeningService {
  _SlowService(this.classifier);

  final _SlowClassifier classifier;
  var cancelCalls = 0;

  @override
  Future<void> startRecording() async {}

  @override
  Future<ScreeningResult> stopAndClassify() => classifier.classifyPcm16kHzMono(Uint8List(0));

  @override
  void cancelAnalysis() {
    cancelCalls++;
    classifier.cancel();
  }
}

void main() {
  group('BackgroundJob', () {
    test('returns the work\'s result', () async {
      final job = BackgroundJob.start(() => 6 * 7);
      expect(await job.result, 42);
    });

    test('reports an error from the work', () async {
      final job = BackgroundJob.start<int>(() => throw StateError('model failed'));
      await expectLater(
        job.result,
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('model failed'))),
      );
    });

    test('keeps the main thread free while the work runs', () async {
      final clock = Stopwatch()..start();
      var last = 0;
      var longest = 0;
      final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
        longest = max(longest, clock.elapsedMilliseconds - last);
        last = clock.elapsedMilliseconds;
      });
      final job = BackgroundJob.start(() => _spin(1500));
      final count = await job.result;
      ticker.cancel();
      expect(count, greaterThan(0));
      // The work blocked its own isolate for 1.5 s; the main one kept ticking.
      expect(longest, lessThan(300));
    });

    test('cancel stops the work and the result says so', () async {
      final job = BackgroundJob.start(() => _spin(20000));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final clock = Stopwatch()..start();
      job.cancel();
      await expectLater(job.result, throwsA(isA<JobCancelled>()));
      expect(clock.elapsedMilliseconds, lessThan(1000));
    });

    test('cancel before the isolate has started still cancels', () async {
      final job = BackgroundJob.start(() => _spin(20000));
      job.cancel();
      await expectLater(job.result, throwsA(isA<JobCancelled>()));
    });

    test('cancel after it finished changes nothing', () async {
      final job = BackgroundJob.start(() => 1);
      expect(await job.result, 1);
      job.cancel();
      expect(await job.result, 1);
    });
  });

  group('YAMNet windowing, as the background isolate runs it', () {
    List<double> scores({double respiratory = 0}) {
      final s = List<double>.filled(521, 0.0);
      s[42] = respiratory; // Cough
      s[0] = 0.9; // Speech: not respiratory, must be ignored
      return s;
    }

    test('scores half-overlapping windows over the whole capture', () {
      var windows = 0;
      yamnetResultFromAudio(
        _pcm(15600 * 3),
        inputSize: 15600,
        scoreWindow: (_) {
          windows++;
          return scores();
        },
      );
      // 46,800 samples, 15,600 per window, stepping 7,800: 5 windows.
      expect(windows, 5);
    });

    test('no respiratory evidence is INCONCLUSIVE, never GREEN', () {
      final result = yamnetResultFromAudio(
        _pcm(15600 * 2),
        inputSize: 15600,
        scoreWindow: (_) => scores(),
      );
      expect(result.label, 'INCONCLUSIVE');
      expect(result.source, 'yamnet');
      expect(result.reason, contains('No respiratory-class evidence'));
    });

    test('the strongest respiratory window decides', () {
      var call = 0;
      final result = yamnetResultFromAudio(
        _pcm(15600 * 2),
        inputSize: 15600,
        scoreWindow: (_) => scores(respiratory: ++call == 2 ? 0.95 : 0.1),
      );
      expect(result.label, 'RED');
      expect(result.confidence, 0.95);
    });

    test('a capture shorter than a window is padded and scored once', () {
      List<double>? seen;
      yamnetResultFromAudio(
        _pcm(1000),
        inputSize: 15600,
        scoreWindow: (window) {
          seen = List.of(window);
          return scores();
        },
      );
      expect(seen, hasLength(15600));
      expect(seen![999], closeTo(0.25, 0.001));
      expect(seen![1000], 0.0);
    });

    test('empty audio is INCONCLUSIVE without running the model', () {
      var ran = false;
      final result = yamnetResultFromAudio(
        Uint8List(0),
        inputSize: 15600,
        scoreWindow: (_) {
          ran = true;
          return scores();
        },
      );
      expect(ran, isFalse);
      expect(result.label, 'INCONCLUSIVE');
    });
  });

  group('ScreeningService cancel', () {
    test('cancelling during analysis returns the cancelled result', () async {
      final classifier = _SlowClassifier();
      final service = ScreeningService(classifier: classifier, recorder: _FakeRecorder());
      final analysis = service.stopAndClassify();
      await Future<void>.delayed(Duration.zero);
      service.cancelAnalysis();
      final result = await analysis;
      expect(classifier.cancelled, isTrue);
      expect(result.label, 'INCONCLUSIVE');
      expect(result.source, 'cancelled');
    }, skip: ScreeningConfig.moewsOnly ? 'needs MOEWS_ONLY=false' : false);
  });

  group('screening screen during analysis', () {
    Future<_SlowService> analyse(WidgetTester tester) async {
      final service = _SlowService(_SlowClassifier());
      await tester.pumpWidget(
        MaterialApp(home: ScreeningScreen(forceWebSimulator: false, service: service)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Stop & Analyze Early'));
      await tester.pump(const Duration(milliseconds: 100));
      return service;
    }

    testWidgets('shows progress and a Cancel button', (tester) async {
      final service = await analyse(tester);
      expect(find.byKey(const Key('screening_progress')), findsOneWidget);
      expect(find.byKey(const Key('screening_cancel')), findsOneWidget);
      expect(find.text('Stop & Analyze Early'), findsNothing);
      service.classifier.finish.complete(unavailableResult());
      await tester.pumpAndSettle();
    });

    testWidgets('Cancel stops the analysis and goes on to vitals', (tester) async {
      final service = await analyse(tester);
      await tester.tap(find.byKey(const Key('screening_cancel')));
      await tester.pumpAndSettle();

      expect(service.cancelCalls, 1);
      expect(service.classifier.cancelled, isTrue);
      final result = tester.widget<VitalsScreen>(find.byType(VitalsScreen)).result;
      expect(result.label, 'INCONCLUSIVE');
      expect(result.source, 'cancelled');
    });

    testWidgets('leaving the screen during analysis stops it', (tester) async {
      final service = await analyse(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(service.cancelCalls, 1);
    });

    testWidgets('the screen keeps drawing frames during analysis', (tester) async {
      final service = await analyse(tester);
      // Progress is animated, so each pump has a frame to draw.
      expect(tester.hasRunningAnimations, isTrue);
      service.classifier.finish.complete(unavailableResult());
      await tester.pumpAndSettle();
    });
  });
}
