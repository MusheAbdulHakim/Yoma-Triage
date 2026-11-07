/// Scenario 1 (BUG-1): the bundled models on a real runtime, fed audio files, not the mic.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:yoma_triage/config.dart';
import 'package:yoma_triage/services/opera_ce_classifier.dart';
import 'package:yoma_triage/services/screening_model_factory.dart';
import 'package:yoma_triage/services/yamnet_classifier.dart';

import 'support/harness.dart';

const _sampleRate = 16000;
const _seconds = 8;
const _operaAsset = 'assets/models/opera_ce_encoder.tflite';

Uint8List _silence() => Uint8List(_sampleRate * _seconds * 2);

Uint8List _tone({double hz = 440, int seconds = _seconds}) {
  final bytes = ByteData(_sampleRate * seconds * 2);
  for (var i = 0; i < _sampleRate * seconds; i++) {
    final sample = (sin(2 * pi * hz * i / _sampleRate) * 0.5 * 32767).round();
    bytes.setInt16(i * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Future<Map<String, Uint8List>> _clips() async => {
      'abnormal_0.wav': Uint8List.fromList(await Host.fixture('abnormal_0.wav')),
      'normal_0.wav': Uint8List.fromList(await Host.fixture('normal_0.wav')),
      'silence': _silence(),
      'tone_440hz': _tone(),
    };

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the bundled YAMNet gives 521 scores', (tester) async {
    await rootBundle.load('assets/models/yamnet.tflite');
    final interpreter = await Interpreter.fromAsset('assets/models/yamnet.tflite');
    addTearDown(interpreter.close);

    final inputShape = interpreter.getInputTensors().first.shape;
    final outputShape = interpreter.getOutputTensors().first.shape;
    await Host.note('YAMNet input tensor $inputShape, output tensor $outputShape');
    expect(outputShape.reduce((a, b) => a * b), 521);

    final input = List<double>.filled(inputShape.reduce((a, b) => a * b), 0.0);
    final output = [List<double>.filled(521, -1.0)];
    interpreter.run(input, output);

    expect(output[0], hasLength(521));
    expect(output[0].every((s) => s.isFinite), isTrue);
    expect(output[0].any((s) => s != -1.0), isTrue, reason: 'scores were not written');
  });

  // Evidence for the report: what the model really outputs for each clip.
  testWidgets('record YAMNet raw scores', (tester) async {
    final interpreter = await Interpreter.fromAsset('assets/models/yamnet.tflite');
    addTearDown(interpreter.close);
    final inputTensor = interpreter.getInputTensors().first;
    final outputTensor = interpreter.getOutputTensors().first;
    await Host.note('YAMNet tensor types: in ${inputTensor.type}, out ${outputTensor.type}, '
        '${interpreter.getOutputTensors().length} outputs');
    const window = 15600;
    for (final clip in (await _clips()).entries) {
      final view = ByteData.sublistView(clip.value);
      final start = clip.value.length > 44 && clip.key.endsWith('.wav') ? 44 : 0;
      final input = List<double>.generate(
        window,
        (i) => view.getInt16(start + i * 2, Endian.little) / 32768.0,
      );
      final output = [List<double>.filled(521, 0.0)];
      interpreter.run(input, output);
      final scores = output[0];
      final ranked = List<int>.generate(521, (i) => i)
        ..sort((a, b) => scores[b].compareTo(scores[a]));
      final top = ranked.take(5).map((i) => '$i=${scores[i].toStringAsFixed(4)}').join(', ');
      final respiratory = [36, 37, 39, 40, 41, 42]
          .map((i) => '$i=${scores[i].toStringAsExponential(2)}')
          .join(', ');
      final nonZero = scores.where((v) => v != 0).length;
      await Host.note('YAMNet raw ${clip.key}: top $top; respiratory $respiratory; '
          '$nonZero of 521 non-zero; sum ${scores.reduce((a, b) => a + b).toStringAsFixed(3)}');
    }
  });

  testWidgets('YAMNet classifies each clip, without falling back', (tester) async {
    final stopwatch = Stopwatch()..start();
    final classifier = await createYamnetClassifier();
    await Host.metric('yamnet_load_ms', stopwatch.elapsedMilliseconds);
    addTearDown(classifier.dispose);

    for (final clip in (await _clips()).entries) {
      stopwatch.reset();
      final result = await classifier.classifyPcm16kHzMono(clip.value);
      final ms = stopwatch.elapsedMilliseconds;
      await Host.metric('yamnet_ms_${clip.key}', ms);
      await Host.note(
        'YAMNet ${clip.key}: ${result.label}, confidence '
        '${result.confidence.toStringAsFixed(4)}, source ${result.source}, '
        'model ${result.modelVersion}, "${result.reason}", $ms ms',
      );

      expect(result.source, 'yamnet', reason: '${clip.key} fell back: ${result.reason}');
      expect(result.source, isNot('stub'));
      expect(result.label, isIn(['RED', 'INCONCLUSIVE']), reason: clip.key);
      expect(result.label, isNot('GREEN'), reason: clip.key);
    }
  });

  // The clip the app really records. Evidence for the report: this all runs in one go on the
  // thread that also answers touches.
  testWidgets('record YAMNet time on a full-length capture', (tester) async {
    final classifier = await createYamnetClassifier();
    addTearDown(classifier.dispose);
    final seconds = ScreeningConfig.durationSec;
    const samples = 3;
    for (var i = 0; i < samples; i++) {
      final stopwatch = Stopwatch()..start();
      final result = await classifier.classifyPcm16kHzMono(_tone(seconds: seconds));
      final ms = stopwatch.elapsedMilliseconds;
      await Host.metric('yamnet_ms_full_capture_${seconds}s_run${i + 1}', ms);
      await Host.note('YAMNet full ${seconds}s capture, run ${i + 1}: ${result.label}, $ms ms');
      expect(result.source, 'yamnet');
    }
  });

  testWidgets('the app picks the real model when acoustic screening is on', (tester) async {
    expect(ScreeningConfig.moewsOnly, isFalse, reason: 'run with MOEWS_ONLY=false');
    expect(ScreeningConfig.model, 'yamnet');
    final classifier = await createConfiguredClassifier();
    addTearDown(classifier.dispose);
    final result = await classifier.classifyPcm16kHzMono(_tone());
    expect(result.source, 'yamnet', reason: result.reason);
  });

  // Evidence for the report: the classifier reports any load failure as "not installed".
  testWidgets('record why the OPERA-CE encoder does or does not load', (tester) async {
    try {
      final data = await rootBundle.load(_operaAsset);
      await Host.note('OPERA-CE asset loads: ${data.lengthInBytes} bytes');
      final encoder = await Interpreter.fromAsset(_operaAsset);
      addTearDown(encoder.close);
      final input = encoder.getInputTensors().first;
      final output = encoder.getOutputTensors().first;
      await Host.note('OPERA-CE tensors: in ${input.shape} ${input.type}, '
          'out ${output.shape} ${output.type}');
      final size = input.shape.reduce((a, b) => a * b);
      try {
        encoder.run(
          List<double>.filled(size, 0.0),
          [List<double>.filled(output.shape.reduce((a, b) => a * b), 0.0)],
        );
        await Host.note('OPERA-CE probe with a flat input: ran');
      } catch (e) {
        await Host.note('OPERA-CE probe with a flat input failed: $e');
      }
    } catch (e) {
      await Host.note('OPERA-CE encoder failed to load: $e');
    }
  });

  testWidgets('OPERA-CE returns INCONCLUSIVE without crashing', (tester) async {
    final classifier = await createOperaCeClassifier();
    addTearDown(classifier.dispose);
    for (final clip in (await _clips()).entries) {
      final stopwatch = Stopwatch()..start();
      final result = await classifier.classifyPcm16kHzMono(clip.value);
      final ms = stopwatch.elapsedMilliseconds;
      await Host.metric('opera_ce_ms_${clip.key}', ms);
      await Host.note(
        'OPERA-CE ${clip.key}: ${result.label}, model ${result.modelVersion}, '
        '"${result.reason}", $ms ms',
      );
      expect(result.label, 'INCONCLUSIVE', reason: clip.key);
    }
  });
}
