import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'audio_pcm.dart';
import 'background_job.dart';
import 'screening_result.dart';
import 'tflite_output.dart';
import 'yamnet_classifier_base.dart';

/// Native (Android/iOS): real YAMNet when the asset loads and tensors match;
/// otherwise INCONCLUSIVE.
///
/// Inference runs in a background isolate ([BackgroundJob]), never on the main thread:
/// a full capture takes several seconds, and a blocked main thread freezes the screen and
/// makes Android report the app as not responding.
class YamnetClassifierIo implements YamnetClassifier {
  YamnetClassifierIo._live(this._model, this._inputSize, this._outputSize);

  static const asset = 'assets/models/yamnet.tflite';

  /// The model file, handed to each background isolate, which loads its own interpreter.
  final Uint8List _model;
  final int _inputSize;
  final int _outputSize;
  BackgroundJob<ScreeningResult>? _job;

  static Future<YamnetClassifier> create() async {
    try {
      final data = await rootBundle.load(asset);
      final model = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      // Loading and the first run happen off the main thread too.
      final (inputSize, outputSize) =
          await BackgroundJob.start(() => _probeYamnet(model), name: 'yamnet-load').result;
      return YamnetClassifierIo._live(model, inputSize, outputSize);
    } catch (_) {
      return _UnavailableClassifier();
    }
  }

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    final job = _startClassifying(_model, _inputSize, _outputSize, pcmBytes);
    _job = job;
    try {
      return await job.result;
    } on JobCancelled {
      return cancelledResult();
    } catch (_) {
      return unavailableResult();
    } finally {
      if (identical(_job, job)) _job = null;
    }
  }

  @override
  void cancel() => _job?.cancel();

  @override
  Future<void> dispose() async => cancel();
}

/// Top level, so the closure sent to the isolate can't capture the classifier.
BackgroundJob<ScreeningResult> _startClassifying(
  Uint8List model,
  int inputSize,
  int outputSize,
  Uint8List pcmBytes,
) =>
    BackgroundJob.start(
      () => _classifyInBackground(model, inputSize, outputSize, pcmBytes),
      name: 'yamnet',
    );

/// Loads the model and runs it once on silence. Returns the input and output sizes.
(int, int) _probeYamnet(Uint8List model) {
  final interpreter = Interpreter.fromBuffer(model);
  try {
    final inTensors = interpreter.getInputTensors();
    final outTensors = interpreter.getOutputTensors();
    if (inTensors.isEmpty || outTensors.isEmpty) {
      throw StateError('YAMNet has no input or output tensor');
    }
    final inputSize = inTensors.first.shape.isEmpty
        ? 15600
        : inTensors.first.shape.reduce((a, b) => a * b);
    final outputSize = outTensors.first.shape.isEmpty
        ? 521
        : outTensors.first.shape.reduce((a, b) => a * b);
    if (inputSize <= 0 || outputSize <= 0) {
      throw StateError('YAMNet tensor sizes are invalid');
    }
    interpreter.run(List<double>.filled(inputSize, 0.0), singleBatchOutput(outputSize));
    return (inputSize, outputSize);
  } finally {
    interpreter.close();
  }
}

ScreeningResult _classifyInBackground(
  Uint8List model,
  int inputSize,
  int outputSize,
  Uint8List pcmBytes,
) {
  final interpreter = Interpreter.fromBuffer(model);
  try {
    final output = singleBatchOutput(outputSize);
    return yamnetResultFromAudio(
      pcmBytes,
      inputSize: inputSize,
      scoreWindow: (window) {
        interpreter.run(window, output);
        return output[0];
      },
    );
  } finally {
    interpreter.close();
  }
}

/// AudioSet YAMNet class indices for cough / wheeze / breathing / gasp.
/// See yamnet_class_map.csv (Google AudioSet).
const yamnetRespiratoryClassIndices = <int>{
  36, // Breathing
  37, // Wheeze
  39, // Gasp
  40, // Pant
  41, // Snort
  42, // Cough
};

/// Scores the capture in half-overlapping windows of [inputSize] samples, and maps the
/// strongest respiratory-class score to a result. [scoreWindow] runs the model on one
/// window and returns its class scores.
ScreeningResult yamnetResultFromAudio(
  Uint8List pcmBytes, {
  required int inputSize,
  required List<double> Function(List<double> window) scoreWindow,
}) {
  final samples = pcm16ToFloat(stripWavHeader(pcmBytes));
  if (samples.isEmpty) {
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason: 'Empty audio — use clinical judgment',
      source: 'yamnet',
      modelVersion: 'yamnet-audioset-v0',
    );
  }

  var maxAbnormal = 0.0;
  var sawRespiratory = false;
  var offset = 0;
  final input = List<double>.filled(inputSize, 0.0);

  void score() {
    final abnormal = _respiratoryAbnormalScore(scoreWindow(input));
    if (abnormal != null) {
      sawRespiratory = true;
      if (abnormal > maxAbnormal) maxAbnormal = abnormal;
    }
  }

  while (offset + inputSize <= samples.length) {
    for (var i = 0; i < inputSize; i++) {
      input[i] = samples[offset + i];
    }
    score();
    offset += inputSize ~/ 2;
  }

  // Shorter than one window: pad with silence and score it once.
  if (offset == 0) {
    for (var i = 0; i < inputSize; i++) {
      input[i] = i < samples.length ? samples[i] : 0.0;
    }
    score();
  }

  if (!sawRespiratory) {
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason: 'No respiratory-class evidence — use MOEWS and clinical judgment',
      source: 'yamnet',
      modelVersion: 'yamnet-audioset-v0',
    );
  }

  return mapYamnetToResult(abnormalScore: maxAbnormal);
}

double? _respiratoryAbnormalScore(List<double> scores) {
  if (scores.isEmpty) return null;

  var maxRespiratory = 0.0;
  for (final idx in yamnetRespiratoryClassIndices) {
    if (idx < scores.length && scores[idx] > maxRespiratory) {
      maxRespiratory = scores[idx];
    }
  }
  // Do not fall back to top-5 AudioSet classes — unrelated labels must not
  // drive clinical-looking GREEN/RED.
  if (maxRespiratory > 0) return maxRespiratory;
  return null;
}

class _UnavailableClassifier implements YamnetClassifier {
  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async =>
      unavailableResult();

  @override
  void cancel() {}

  @override
  Future<void> dispose() async {}
}

Future<YamnetClassifier> createYamnetClassifier() =>
    YamnetClassifierIo.create();
